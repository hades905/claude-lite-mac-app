import Foundation

public enum ConnectionStatus: String, Codable, Equatable, Sendable {
    case checking
    case connected
    case disconnected
    case authFailed

    public var label: String {
        switch self {
        case .checking:
            "Checking"
        case .connected:
            "Connected"
        case .disconnected:
            "Disconnected"
        case .authFailed:
            "Auth Failed"
        }
    }
}
