import Foundation

enum UsageFormat {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func percentOrDash(_ value: Double?) -> String {
        value.map(percent) ?? "--"
    }

    // Relative inside the hour, a weekday and time inside the week, a date
    // beyond that: "Resets in 51 min", "Resets Thu 12:00 AM", "Resets Sep 10".
    static func resetText(_ resetsAt: Date?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        if seconds <= 0 { return "Resets now" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "Resets in \(max(minutes, 1)) min" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: resetsAt)).day ?? 0
        formatter.dateFormat = days >= 7 ? "MMM d" : "E h:mm a"
        return "Resets \(formatter.string(from: resetsAt))"
    }

    // Codex data comes from the last session, which may be days old.
    static func staleText(_ fetchedAt: Date, now: Date = Date()) -> String? {
        guard now.timeIntervalSince(fetchedAt) > 3600 else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "as of \(f.string(from: fetchedAt))"
    }

    static func uptime(since start: Date?, now: Date = Date()) -> String? {
        guard let start else { return nil }
        let seconds = Int(now.timeIntervalSince(start))
        if seconds < 60 { return "\(max(seconds, 0))s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    static func memory(_ bytes: UInt64?) -> String? {
        guard let bytes else { return nil }
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useMB, .useGB]
        return f.string(fromByteCount: Int64(bytes))
    }

    static func cpu(_ percent: Double?) -> String? {
        guard let percent else { return nil }
        return String(format: "%.0f%%", percent)
    }
}
