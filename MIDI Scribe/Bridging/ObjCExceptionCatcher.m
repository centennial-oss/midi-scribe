#import "ObjCExceptionCatcher.h"

BOOL MSCatchObjCException(NS_NOESCAPE void (^block)(void),
                          NSError *_Nullable *_Nullable errorOut) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (errorOut != NULL) {
            NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [NSMutableDictionary dictionary];
            if (exception.name != nil) {
                userInfo[@"ExceptionName"] = exception.name;
            }
            if (exception.reason != nil) {
                userInfo[NSLocalizedDescriptionKey] = exception.reason;
                userInfo[@"ExceptionReason"] = exception.reason;
            }
            if (exception.callStackSymbols != nil) {
                userInfo[@"ExceptionCallStackSymbols"] = exception.callStackSymbols;
            }
            if (exception.userInfo != nil) {
                userInfo[@"ExceptionUserInfo"] = exception.userInfo;
            }
            *errorOut = [NSError errorWithDomain:@"org.centennialoss.midiscribe.ObjCException"
                                            code:-1
                                        userInfo:userInfo];
        }
        return NO;
    }
}
