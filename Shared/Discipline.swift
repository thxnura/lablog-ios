import SwiftUI

/// Visual identity per lab discipline, derived from the lab code prefix.
struct Discipline {
    let symbol: String
    let colors: [Color]
    var tint: Color { colors[0] }
    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func of(labCode code: String) -> Discipline {
        switch code.uppercased().prefix(3) {
        case "CHE":
            Discipline(symbol: "flask.fill", colors: [Color(red: 0.05, green: 0.62, blue: 0.58), Color(red: 0.13, green: 0.45, blue: 0.80)])
        case "PHY":
            Discipline(symbol: "atom", colors: [Color(red: 0.42, green: 0.32, blue: 0.94), Color(red: 0.71, green: 0.31, blue: 0.86)])
        case "BIO":
            Discipline(symbol: "leaf.fill", colors: [Color(red: 0.20, green: 0.66, blue: 0.33), Color(red: 0.05, green: 0.55, blue: 0.52)])
        default:
            Discipline(symbol: "testtube.2", colors: [Color(red: 0.30, green: 0.36, blue: 0.93), Color(red: 0.20, green: 0.55, blue: 0.95)])
        }
    }
}
