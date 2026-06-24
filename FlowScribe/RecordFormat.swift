import Foundation

/// Formatage partagé des transcriptions (date au format système 24 h, durée mm:ss).
enum RecordFormat {
    static func dateLabel(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) {
            return "Aujourd'hui à " + d.formatted(.dateTime.hour().minute())
        }
        return d.formatted(.dateTime.day().month().year().hour().minute())
    }

    static func duration(_ d: TimeInterval) -> String {
        let s = Int(d.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
