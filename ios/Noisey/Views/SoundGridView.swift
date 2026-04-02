import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct SoundGridView: View {
    @Environment(NoiseyStore.self) private var store
    @State private var showingUpload = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Sound grid
                    soundsSection

                    sectionDivider

                    // Sleep timer
                    SleepTimerView()

                    sectionDivider

                    // Schedule
                    ScheduleView()

                    sectionDivider

                    // Speaker output
                    speakerSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.horizontal, 4)
    }

    private var soundsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(store.currentWorldConfig.displayName.lowercased())

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.currentWorldSounds) { sound in
                    SoundCardView(
                        sound: sound,
                        isActive: sound.active,
                        onTap: {
                            store.toggleSound(id: sound.id)
                        },
                        onDelete: sound.category == .custom ? {
                            store.deleteSound(id: sound.id)
                        } : nil
                    )
                }

                // Upload button — ghost glass to match the grid
                Button {
                    showingUpload = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        Text("upload")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular.interactive(true))
                    .opacity(0.5)
                }
                .buttonStyle(.plain)
                .fileImporter(
                    isPresented: $showingUpload,
                    allowedContentTypes: [.audio, .wav, .mp3, .aiff],
                    allowsMultipleSelection: false
                ) { result in
                    guard case .success(let urls) = result, let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    store.uploadSound(
                        fileURL: url,
                        name: url.deletingPathExtension().lastPathComponent
                    )
                }
            }
        }
    }

    private var speakerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("speaker")

            HStack {
                Text("select speaker")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                RoutePickerView()
                    .frame(width: 36, height: 36)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(.regular)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

// MARK: - AVRoutePickerView Wrapper

struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .systemBlue
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
