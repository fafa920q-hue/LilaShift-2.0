// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Read-only live MobileGestalt probe (MGCopyAnswer). Device-only; every
/// query returns `nil` in the simulator, and the checkup renders "live:
/// unknown" there — never a faked value. The probe returns system
/// capability answers, no user data.
enum LiveGestaltProbe {
    static func queryBool(_ key: String) -> Bool? {
        (GXCopyLiveGestaltAnswer(key) as? NSNumber)?.boolValue
    }

    static func queryString(_ key: String) -> String? {
        GXCopyLiveGestaltAnswer(key) as? String
    }
}
