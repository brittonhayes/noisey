import Foundation

enum SoundCategory: String, Codable, Sendable {
    case noise
    case nature
    case custom
}

struct SoundEntry: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let category: SoundCategory
    var active: Bool
    var description: String?
    var recordedAt: String?
    var durationSecs: Float?
}
