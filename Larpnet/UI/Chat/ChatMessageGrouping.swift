import Foundation

/// Groups a flat `[ChatMessage]` timeline into day sections, each holding sender/time clusters
/// -- the WhatsApp/Telegram/iMessage convention of collapsing consecutive same-sender messages
/// into one visual block instead of repeating an avatar/name/bubble-decoration per message.
/// Pure data transform, no view code, so the clustering rule is easy to reason about/tune
/// independently of `ChatThreadView`'s layout.
struct ChatMessageGrouping {
    /// Consecutive messages from the same sender collapse into one cluster as long as they're
    /// this close together -- matches the common WhatsApp/Telegram convention.
    static let clusterWindow: TimeInterval = 60

    struct Cluster: Identifiable {
        let id: String
        let isOwn: Bool
        let senderId: String?
        let senderDisplayName: String?
        let senderAvatarUrl: String?
        let messages: [ChatMessage]
    }

    struct DaySection: Identifiable {
        let id: String
        let date: Date
        let clusters: [Cluster]
    }

    static func build(from messages: [ChatMessage]) -> [DaySection] {
        let calendar = Calendar.current
        var sections: [DaySection] = []
        var currentDayMessages: [ChatMessage] = []
        var currentDay: Date?

        func flushDay() {
            guard let day = currentDay, !currentDayMessages.isEmpty else { return }
            sections.append(DaySection(id: day.description, date: day, clusters: clusters(from: currentDayMessages)))
            currentDayMessages = []
        }

        for message in messages {
            let day = calendar.startOfDay(for: message.timestamp)
            if currentDay == nil {
                currentDay = day
            } else if day != currentDay {
                flushDay()
                currentDay = day
            }
            currentDayMessages.append(message)
        }
        flushDay()
        return sections
    }

    /// A stable grouping key: "self" for the local user, else the sender's mxid (falling back to
    /// a constant so two consecutive messages with no reported sender id still cluster together
    /// rather than each starting a new cluster).
    private static func clusterKey(for message: ChatMessage) -> String {
        message.isOwn ? "self" : (message.senderId ?? "unknown-sender")
    }

    private static func clusters(from messages: [ChatMessage]) -> [Cluster] {
        var clusters: [Cluster] = []
        for message in messages {
            let key = clusterKey(for: message)
            if let last = clusters.last, clusterKey(for: last.messages[0]) == key,
               let lastTimestamp = last.messages.last?.timestamp,
               message.timestamp.timeIntervalSince(lastTimestamp) <= clusterWindow {
                clusters[clusters.count - 1] = Cluster(
                    id: last.id, isOwn: last.isOwn, senderId: last.senderId,
                    senderDisplayName: last.senderDisplayName, senderAvatarUrl: last.senderAvatarUrl,
                    messages: last.messages + [message]
                )
            } else {
                clusters.append(Cluster(
                    id: message.id, isOwn: message.isOwn, senderId: message.senderId,
                    senderDisplayName: message.senderDisplayName, senderAvatarUrl: message.senderAvatarUrl,
                    messages: [message]
                ))
            }
        }
        return clusters
    }

    /// "Today" / "Yesterday" / a localized date, for the day-separator pill.
    static func dayLabel(for date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "d MMMM" : "d MMMM yyyy"
        return formatter.string(from: date)
    }
}
