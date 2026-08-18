import Foundation

/// Short relative-time labels for status/notification timestamps (e.g. "2h", "3d"), the
/// counterpart of Android's `ui/common/RelativeTime.kt`.
enum RelativeTime {
    static func short(from date: Date, relativeTo now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        case ..<(86400 * 7): return "\(Int(seconds / 86400))d"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            return formatter.string(from: date)
        }
    }
}
