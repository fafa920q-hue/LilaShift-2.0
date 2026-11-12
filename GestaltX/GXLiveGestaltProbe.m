// SPDX-License-Identifier: GPL-3.0-only
#import "GXLiveGestaltProbe.h"
#import <TargetConditionals.h>
#import <dlfcn.h>

id _Nullable GXCopyLiveGestaltAnswer(NSString *key) {
#if TARGET_OS_SIMULATOR
    (void)key;
    return nil;
#else
    static CFTypeRef (*copyAnswer)(CFStringRef) = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Keep the library loaded. No query hooks, library writes or device writes.
        void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY | RTLD_LOCAL);
        if (handle) copyAnswer = (CFTypeRef (*)(CFStringRef))dlsym(handle, "MGCopyAnswer");
    });
    if (!copyAnswer) return nil;
    // MGCopyAnswer follows the +1 Copy rule; transfer ownership to ARC.
    CFTypeRef value = copyAnswer((__bridge CFStringRef)key);
    return value ? (__bridge_transfer id)value : nil;
#endif
}
