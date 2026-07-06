// Tier 1 (bring-your-own-endpoint) enhancement: one OpenAI-compatible call
// path that the other tiers will reuse. Talks to LM Studio, Ollama, or any
// /v1-style server.

import Foundation

// MARK: - Config

/// Where to send enhancement calls. The failable init validates transport:
/// https to any host, plain http only to loopback or private LAN hosts.
public struct EndpointConfig: Sendable, Equatable {
    public var baseURL: URL // e.g. http://localhost:1234/v1
    public var apiKey: String?
    public var model: String

    /// Returns nil for URLs without a scheme+host, for plain http to a
    /// non-local host, and for API keys containing control characters.
    /// The key is trimmed; an empty key becomes nil.
    public init?(baseURL: URL, apiKey: String? = nil, model: String) {
        guard let scheme = baseURL.scheme?.lowercased(),
              let host = baseURL.host(), !host.isEmpty else { return nil }
        switch scheme {
        case "https":
            break
        case "http":
            guard Self.isLoopbackOrPrivate(host) else { return nil }
        default:
            return nil
        }
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedKey.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        self.baseURL = baseURL
        self.apiKey = trimmedKey.isEmpty ? nil : trimmedKey
        self.model = model
    }

    /// Convenience for manual testing: reads "enhancerBaseURL" / "enhancerModel"
    /// from UserDefaults and the API key from the AWESOMEETING_API_KEY
    /// environment variable. Secrets never live in UserDefaults; Keychain
    /// wiring for the key arrives with the settings piece.
    public init?(userDefaults: UserDefaults = .standard) {
        guard let urlString = userDefaults.string(forKey: "enhancerBaseURL"),
              let url = URL(string: urlString),
              let model = userDefaults.string(forKey: "enhancerModel") else { return nil }
        self.init(baseURL: url,
                  apiKey: ProcessInfo.processInfo.environment["AWESOMEETING_API_KEY"],
                  model: model)
    }

    /// Loopback (localhost/127.0.0.0/8/::1), RFC1918 private IPv4
    /// (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16), .local hostnames, and
    /// link-local (169.254.0.0/16, fe80::) count as local.
    // ponytail: string checks cover the documented cases; real IP parsing
    // can arrive with the settings piece if edge cases show up.
    static func isLoopbackOrPrivate(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h == "::1" || h.hasSuffix(".local") || h.hasPrefix("fe80:") {
            return true
        }
        let octets = h.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}

// MARK: - Errors

/// Human-readable; `errorDescription` is plain UI copy, `debugDescription`
/// keeps the raw server body for the future Test-connection UI.
public enum OpenAIClientError: Error, LocalizedError, CustomDebugStringConvertible, Sendable, Equatable {
    case notHTTP
    /// `message` is the decoded OpenAI error-envelope message when the body
    /// carries one, otherwise the raw body snippet; `rawBody` is always the
    /// raw snippet (first 300 characters).
    case httpError(status: Int, message: String, rawBody: String)
    case emptyResponse
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .notHTTP:
            "The endpoint did not return an HTTP response."
        case .httpError(let status, let message, _):
            switch status {
            case 401, 403:
                "The server rejected the API key. Check the key in settings. (\(status))"
            case 404:
                "Nothing answered at that address. Check the endpoint address in settings. (\(status))"
            case 500...:
                "The server had a problem: \(message). Check that the model is loaded. (\(status))"
            default:
                message.isEmpty
                    ? "The server returned an error. (\(status))"
                    : "The server returned an error: \(message). (\(status))"
            }
        case .emptyResponse:
            "The endpoint returned a response with no content."
        case .malformedResponse:
            "The server replied, but not in the expected format. Check that the endpoint address points at an OpenAI-compatible /v1 server."
        }
    }

    public var debugDescription: String {
        switch self {
        case .httpError(let status, _, let rawBody):
            "HTTP \(status): \(rawBody)"
        default:
            errorDescription ?? String(describing: self)
        }
    }
}

// MARK: - Client

public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Minimal OpenAI-compatible HTTP client: chat completions + model listing
/// (the latter doubles as the "Test connection" affordance).
/// Construct once and reuse it across calls so the URLSession is reused.
public struct OpenAICompatibleClient: Sendable {
    let config: EndpointConfig
    let session: URLSession

    public init(config: EndpointConfig, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForResource = 300
            self.session = URLSession(configuration: cfg)
        }
    }

    /// POST {baseURL}/chat/completions; returns the first choice's content,
    /// trimmed. Nil or whitespace-only content throws `emptyResponse`.
    public func chatCompletion(messages: [ChatMessage]) async throws -> String {
        struct Body: Encodable {
            let model: String
            let messages: [ChatMessage]
            let stream: Bool
        }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        // URLRequest's baked-in 60s default overrides the session config, so
        // the long generation timeout must live on the request itself.
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            Body(model: config.model, messages: messages, stream: false))
        let data = try await validatedData(for: request)
        let content = try decode(Response.self, from: data)
            .choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let content, !content.isEmpty else { throw OpenAIClientError.emptyResponse }
        return content
    }

    /// GET {baseURL}/models; returns model ids. Doubles as "Test connection".
    public func listModels() async throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        var request = URLRequest(url: config.baseURL.appending(path: "models"))
        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let data = try await validatedData(for: request)
        return try decode(Response.self, from: data).data.map(\.id)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch is DecodingError {
            throw OpenAIClientError.malformedResponse
        }
    }

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIClientError.notHTTP }
        guard (200..<300).contains(http.statusCode) else {
            struct ErrorEnvelope: Decodable {
                struct Payload: Decodable { let message: String }
                let error: Payload
            }
            let snippet = String(String(decoding: data, as: UTF8.self).prefix(300))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message ?? snippet
            throw OpenAIClientError.httpError(status: http.statusCode, message: message, rawBody: snippet)
        }
        return data
    }
}
