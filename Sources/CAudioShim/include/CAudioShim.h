#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside @try/@catch and returns any raised NSException bridged
/// to an NSError (nil on normal completion). Swift's do/catch cannot intercept
/// NSExceptions — AVFoundation raises them for API misuse (notably
/// -[AVAudioNode installTapOnBus:...]) and they would otherwise abort the app.
/// The block is non-escaping: it runs synchronously before this returns.
NSError *_Nullable awm_tryBlock(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
