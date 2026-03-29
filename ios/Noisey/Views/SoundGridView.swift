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
                VStack(alignment: .leading, spacing: 28) {
                    // Sound grid
                    soundsSection

                    // Sleep timer
                    SleepTimerView()

                    // Schedule
                    ScheduleView()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("sounds")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var soundsSection: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(store.sounds) { sound in
                SoundCardView(
                    sound: sound,
                    isActive: sound.active,
                    onTap: {
                        Task { await store.toggleSound(id: sound.id) }
                    },
                    onDelete: sound.category == .custom ? {
                        Task { await store.deleteSound(id: sound.id) }
                    } : nil
                )
            }

            // Upload button
            Button {
                showingUpload = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text("upload")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.quaternary)
                )
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
                Task {
                    await store.uploadSound(
                        fileURL: url,
                        name: url.deletingPathExtension().lastPathComponent,
                        description: nil
                    )
                }
            }
        }
    }
}
