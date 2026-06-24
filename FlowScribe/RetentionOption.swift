import Foundation

/// Options de conservation des enregistrements (source unique : jours + libellés).
struct RetentionOption: Identifiable {
    let days: Int   // 0 = toujours (illimité)
    let title: String
    var id: Int { days }

    static let all: [RetentionOption] = [
        .init(days: 1, title: "1 jour"),
        .init(days: 7, title: "1 semaine"),
        .init(days: 15, title: "15 jours"),
        .init(days: 30, title: "30 jours"),
        .init(days: 0, title: "Toujours"),
    ]
    static var dayValues: [Int] { all.map(\.days) }
}
