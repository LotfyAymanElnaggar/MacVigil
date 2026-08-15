import Foundation

enum SessionDuration: String, CaseIterable, Identifiable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case custom
    case indefinite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes: return "15 min"
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .custom: return "Custom"
        case .indefinite: return "Indefinite"
        }
    }

    func interval(customMinutes: Int) -> TimeInterval? {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .custom: return TimeInterval(max(1, customMinutes) * 60)
        case .indefinite: return nil
        }
    }
}

enum RuntimeProfile: String, CaseIterable, Identifiable {
    case computeGuard
    case closedLidEco
    case fullAwake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .computeGuard: return "Compute Guard"
        case .closedLidEco: return "Closed-Lid Eco"
        case .fullAwake: return "Full Awake"
        }
    }

    var subtitle: String {
        switch self {
        case .computeGuard:
            return "Keep compute and network available while the display may sleep."
        case .closedLidEco:
            return "Keep work running with the lid closed while minimizing built-in display use."
        case .fullAwake:
            return "Keep both the Mac and display awake."
        }
    }

    var keepsDisplayAwake: Bool { self == .fullAwake }
    var requiresClosedLidGuard: Bool { self == .closedLidEco }
}
