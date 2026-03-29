import Foundation

struct Schedule: Codable, Sendable {
    var startTime: String
    var stopTime: String
    var soundId: String
    var enabled: Bool
}
