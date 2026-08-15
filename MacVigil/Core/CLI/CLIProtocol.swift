import Foundation

/// Small property-list-safe protocol shared by the menu app and the `macvigil`
/// command-line client. The transport is NSDistributedNotificationCenter, so a
/// CLI invocation always talks to the already-running MacVigil process instead
/// of creating a second power-management runtime.
enum MacVigilCLIProtocol {
    static let requestName = Notification.Name("com.lotfy.macvigil.cli.request")
    static let responseName = Notification.Name("com.lotfy.macvigil.cli.response")
    static let payloadKey = "payload"
}

struct MacVigilCLIRequest: Codable {
    var id: String
    var action: String
    var arguments: [String]
    var options: [String: String]
    var environment: [String: String]

    init(
        id: String = UUID().uuidString,
        action: String,
        arguments: [String] = [],
        options: [String: String] = [:],
        environment: [String: String] = [:]
    ) {
        self.id = id
        self.action = action
        self.arguments = arguments
        self.options = options
        self.environment = environment
    }
}

struct MacVigilCLIResponse: Codable {
    var id: String
    var ok: Bool
    var message: String
    var lines: [String]
    var values: [String: String]

    init(
        id: String,
        ok: Bool,
        message: String,
        lines: [String] = [],
        values: [String: String] = [:]
    ) {
        self.id = id
        self.ok = ok
        self.message = message
        self.lines = lines
        self.values = values
    }
}
