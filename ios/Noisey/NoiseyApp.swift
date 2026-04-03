import SwiftUI

@main
struct NoiseyApp: App {
    @State private var store = NoiseyStore()

    var body: some Scene {
        WindowGroup {
            WorldSwitcherView()
                .environment(store)
        }
    }
}
