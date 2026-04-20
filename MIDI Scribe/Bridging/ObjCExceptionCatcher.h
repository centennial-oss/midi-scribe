#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside an `@try`/`@catch` so that Objective-C exceptions raised by
/// Apple frameworks (notably AVAudioEngine / AVAudioUnitSampler during render-thread
/// races) are turned into recoverable `NSError`s instead of terminating the process.
///
/// Returns `YES` if the block completed normally, `NO` if an exception was caught.
/// When `NO` is returned and `errorOut` is non-NULL, it is populated with an NSError
/// whose userInfo contains the caught exception's `name`, `reason`, and call stack.
BOOL MSCatchObjCException(NS_NOESCAPE void (^block)(void),
                          NSError *_Nullable *_Nullable errorOut);

NS_ASSUME_NONNULL_END
