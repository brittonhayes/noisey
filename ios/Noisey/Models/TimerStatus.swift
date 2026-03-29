import Foundation

struct TimerStatus: Codable, Sendable {
    let remainingSecs: Int
    let durationSecs: Int
}
