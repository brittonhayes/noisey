import SwiftUI

struct SkyObjectView: View {
    @Environment(NoiseyStore.self) private var store

    var body: some View {
        ZStack {
            switch store.currentWorld {
            case .night:
                MoonVolumeView()
                    .transition(.opacity)
            case .day:
                SunVolumeView()
                    .transition(.opacity)
            case .dusk:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.6), value: store.currentWorld)
    }
}
