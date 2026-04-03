import SwiftUI

enum World: String, CaseIterable, Codable, Sendable {
    case night, dusk, day
}

struct WorldConfig {
    let displayName: String
    let backgroundColor: Color
    let backgroundGradientTop: Color
    let backgroundGradientBottom: Color
    let accentColor: Color
    let soundIDs: [String]
    let defaultSoundID: String
    let skyObjectType: SkyObjectType

    enum SkyObjectType {
        case moon, sun, firefly
    }

    /// Background as a smooth vertical gradient.
    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundGradientTop, backgroundGradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func config(for world: World) -> WorldConfig {
        switch world {
        case .night:
            // Deep space indigo — feels infinite and calm
            return WorldConfig(
                displayName: "Night",
                backgroundColor: Color(red: 0.04, green: 0.03, blue: 0.11),
                backgroundGradientTop: Color(red: 0.06, green: 0.04, blue: 0.16),
                backgroundGradientBottom: Color(red: 0.02, green: 0.02, blue: 0.06),
                accentColor: Color(red: 0.72, green: 0.78, blue: 1.0),
                soundIDs: ["midnight-forest"],
                defaultSoundID: "midnight-forest",
                skyObjectType: .moon
            )
        case .day:
            // Soft golden morning — warm peach fading into serene blue
            return WorldConfig(
                displayName: "Day",
                backgroundColor: Color(red: 0.55, green: 0.72, blue: 0.88),
                backgroundGradientTop: Color(red: 0.45, green: 0.65, blue: 0.88),
                backgroundGradientBottom: Color(red: 0.70, green: 0.82, blue: 0.92),
                accentColor: Color(red: 1.0, green: 0.84, blue: 0.40),
                soundIDs: ["morning-birds"],
                defaultSoundID: "morning-birds",
                skyObjectType: .sun
            )
        case .dusk:
            // Twilight pond — dark murky greens
            return WorldConfig(
                displayName: "Dusk",
                backgroundColor: Color(red: 0.03, green: 0.08, blue: 0.06),
                backgroundGradientTop: Color(red: 0.04, green: 0.10, blue: 0.08),
                backgroundGradientBottom: Color(red: 0.02, green: 0.05, blue: 0.04),
                accentColor: Color(red: 1.0, green: 0.62, blue: 0.44),
                soundIDs: ["evening-frogs"],
                defaultSoundID: "evening-frogs",
                skyObjectType: .firefly
            )
        }
    }
}
