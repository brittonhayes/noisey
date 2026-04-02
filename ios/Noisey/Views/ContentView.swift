import SwiftUI

struct ContentView: View {
    @Environment(NoiseyStore.self) private var store
    @State private var showingSounds = false

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.067, green: 0.067, blue: 0.067)
                .ignoresSafeArea()

            // Stars
            StarfieldView(volume: store.masterVolume)

            VStack(spacing: 0) {
                // Status
                statusBar
                    .padding(.top, 8)

                Spacer()

                // Moon
                MoonVolumeView()

                Spacer()

                // Now playing bar
                NowPlayingBar(showingSounds: $showingSounds)
                    .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showingSounds) {
            SoundGridView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .preferredColorScheme(.dark)
    }

    private var statusBar: some View {
        HStack {
            if let timer = store.sleepTimer {
                let mins = timer.remainingSecs / 60
                let secs = timer.remainingSecs % 60
                Text("sleep \(mins)m \(secs)s")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button("cancel") {
                    store.setSleepTimer(minutes: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }
}
