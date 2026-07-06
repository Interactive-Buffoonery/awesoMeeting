// Tier 1 enhancement: client request shape + response decoding against a
// stubbed URLProtocol (no network), config validation, error copy, and
// prompt construction.

import Foundation
import Testing
@testable import AwesoMeetingCore

// Serves canned responses and records the last request. Serialized suite
// below because the recorded state is static.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var response: (status: Int, body: String) = (200, "{}")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            return data
        }
        let http = HTTPURLResponse(
            url: request.url!, statusCode: Self.response.status,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized)
struct OpenAICompatibleClientTests {
    let client: OpenAICompatibleClient

    init() throws {
        // Reset shared stub state so tests never see a previous test's leftovers.
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
        StubURLProtocol.response = (200, "{}")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        client = OpenAICompatibleClient(
            config: try #require(EndpointConfig(
                baseURL: URL(string: "http://localhost:1234/v1")!,
                apiKey: "sk-test", model: "test-model")),
            session: URLSession(configuration: cfg))
    }

    @Test func chatCompletionSendsOpenAIShapeAndDecodesReply() async throws {
        StubURLProtocol.response = (200, #"{"choices":[{"message":{"role":"assistant","content":"Enhanced notes."}}]}"#)

        let reply = try await client.chatCompletion(messages: [
            ChatMessage(role: "system", content: "Be terse."),
            ChatMessage(role: "user", content: "Hello"),
        ])
        #expect(reply == "Enhanced notes.")

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "http://localhost:1234/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 120)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        struct Body: Decodable {
            let model: String
            let messages: [ChatMessage]
            let stream: Bool
        }
        let body = try JSONDecoder().decode(Body.self, from: try #require(StubURLProtocol.lastBody))
        #expect(body.model == "test-model")
        #expect(body.stream == false)
        #expect(body.messages == [
            ChatMessage(role: "system", content: "Be terse."),
            ChatMessage(role: "user", content: "Hello"),
        ])
    }

    @Test func listModelsDecodesIDs() async throws {
        StubURLProtocol.response = (200, #"{"object":"list","data":[{"id":"gemma-3-12b"},{"id":"qwen3-8b"}]}"#)

        let models = try await client.listModels()
        #expect(models == ["gemma-3-12b", "qwen3-8b"])

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "http://localhost:1234/v1/models")
        #expect(request.httpMethod == "GET")
    }

    @Test func nullContentThrowsEmptyResponse() async {
        StubURLProtocol.response = (200, #"{"choices":[{"message":{"role":"assistant","content":null}}]}"#)

        await #expect(throws: OpenAIClientError.emptyResponse) {
            try await client.chatCompletion(messages: [ChatMessage(role: "user", content: "hi")])
        }
    }

    @Test func emptyContentThrowsEmptyResponse() async {
        StubURLProtocol.response = (200, #"{"choices":[{"message":{"role":"assistant","content":""}}]}"#)

        await #expect(throws: OpenAIClientError.emptyResponse) {
            try await client.chatCompletion(messages: [ChatMessage(role: "user", content: "hi")])
        }
    }

    @Test func emptyChoicesThrowsEmptyResponse() async {
        StubURLProtocol.response = (200, #"{"choices":[]}"#)

        await #expect(throws: OpenAIClientError.emptyResponse) {
            try await client.chatCompletion(messages: [ChatMessage(role: "user", content: "hi")])
        }
    }

    @Test func httpErrorCarriesStatusAndBodySnippet() async {
        StubURLProtocol.response = (500, "model not loaded")

        await #expect(throws: OpenAIClientError.httpError(
            status: 500, message: "model not loaded", rawBody: "model not loaded")) {
            try await client.listModels()
        }
        let error = OpenAIClientError.httpError(
            status: 500, message: "model not loaded", rawBody: "model not loaded")
        #expect(error.localizedDescription
            == "The server had a problem: model not loaded. Check that the model is loaded. (500)")
        #expect(error.debugDescription.contains("model not loaded"))
    }

    @Test func errorEnvelope401SurfacesPlainGuidance() async {
        StubURLProtocol.response = (401, #"{"error":{"message":"invalid api key"}}"#)

        do {
            _ = try await client.listModels()
            Issue.record("expected httpError")
        } catch let error as OpenAIClientError {
            guard case .httpError(let status, let message, _) = error else {
                Issue.record("expected httpError, got \(error)")
                return
            }
            #expect(status == 401)
            #expect(message == "invalid api key") // envelope decoded, not the raw JSON
            #expect(error.localizedDescription.contains("The server rejected the API key. Check the key in settings."))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func nonJSONBodyThrowsMalformedResponse() async {
        StubURLProtocol.response = (200, "<html>totally not an OpenAI server</html>")

        await #expect(throws: OpenAIClientError.malformedResponse) {
            try await client.listModels()
        }
    }
}

struct EndpointConfigValidationTests {
    @Test func publicPlainHTTPRejected() {
        #expect(EndpointConfig(baseURL: URL(string: "http://example.com/v1")!, model: "m") == nil)
        #expect(EndpointConfig(baseURL: URL(string: "http://8.8.8.8/v1")!, model: "m") == nil)
    }

    @Test func loopbackAndLANPlainHTTPAccepted() {
        #expect(EndpointConfig(baseURL: URL(string: "http://localhost:1234/v1")!, model: "m") != nil)
        #expect(EndpointConfig(baseURL: URL(string: "http://127.0.0.1:1234/v1")!, model: "m") != nil)
        #expect(EndpointConfig(baseURL: URL(string: "http://192.168.1.20:1234/v1")!, model: "m") != nil)
        #expect(EndpointConfig(baseURL: URL(string: "http://10.0.0.5:8080/v1")!, model: "m") != nil)
        #expect(EndpointConfig(baseURL: URL(string: "http://172.20.0.2/v1")!, model: "m") != nil)
        #expect(EndpointConfig(baseURL: URL(string: "http://studio.local:1234/v1")!, model: "m") != nil)
    }

    @Test func httpsAccepted() {
        #expect(EndpointConfig(baseURL: URL(string: "https://api.example.com/v1")!, model: "m") != nil)
    }

    @Test func schemelessOrHostlessRejected() {
        #expect(EndpointConfig(baseURL: URL(string: "localhost:1234/v1")!, model: "m") == nil)
        #expect(EndpointConfig(baseURL: URL(string: "file:///v1")!, model: "m") == nil)
    }

    @Test func emptyAPIKeyBecomesNil() throws {
        let config = try #require(EndpointConfig(
            baseURL: URL(string: "https://api.example.com/v1")!, apiKey: "  \n", model: "m"))
        #expect(config.apiKey == nil)
    }

    @Test func controlCharacterAPIKeyRejected() {
        #expect(EndpointConfig(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk-\u{07}beep", model: "m") == nil)
    }
}

struct EndpointNotesEnhancerTests {
    @Test func promptCarriesUserNotesAndLabeledTranscriptOnly() {
        let meeting = Meeting(
            id: "m1", title: "Roadmap sync", dateLabel: "Today", duration: "10 min",
            state: .done,
            speakers: [Speaker(id: "s1", name: "Sarah", index: 0)],
            notes: [
                NoteBlock(kind: .user, text: "lock launch date"),
                NoteBlock(kind: .ai, text: "previous AI enhancement"),
            ],
            transcript: [
                TranscriptLine(time: "00:00:04", speakerID: "s1", text: "Let's lock the date."),
            ],
            summary: nil)

        let messages = EndpointNotesEnhancer.promptMessages(for: meeting)
        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[0].content.contains("Never invent"))
        #expect(messages[0].content.contains("level 3 (###)")) // heading discipline

        let user = messages[1]
        #expect(user.role == "user")
        #expect(user.content.contains("Roadmap sync"))
        #expect(user.content.contains("- lock launch date"))
        #expect(user.content.contains("[00:00:04] Sarah: Let's lock the date."))
        #expect(!user.content.contains("previous AI enhancement")) // only the user's own notes go in
    }
}
