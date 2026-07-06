#import "CAudioShim.h"

NSError *_Nullable awm_tryBlock(NS_NOESCAPE void (^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return [NSError errorWithDomain:@"AwesoMeeting.NSException"
                                   code:1
                               userInfo:@{
                                   NSLocalizedDescriptionKey: exception.reason ?: exception.name
                               }];
    }
}
