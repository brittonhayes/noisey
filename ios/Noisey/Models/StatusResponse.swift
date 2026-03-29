import Foundation

struct StatusResponse: Codable, Sendable {
    let sounds: [SoundEntry]
    let masterVolume: Float
    let sleepTimer: TimerStatus?
    let schedule: Schedule?
    let simulate: Bool
}
