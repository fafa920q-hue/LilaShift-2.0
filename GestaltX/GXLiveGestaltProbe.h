// SPDX-License-Identifier: GPL-3.0-only
#import <Foundation/Foundation.h>

// Read-only live MobileGestalt answers via MGCopyAnswer. Returns nil in
// the simulator and when the answer is unavailable. No writes, no hooks.
FOUNDATION_EXPORT id _Nullable GXCopyLiveGestaltAnswer(NSString * _Nonnull key);
