import SwiftUI

struct ServerSetupView: View {
    @Environment(NoiseyStore.self) private var store
    @State private var urlText = "http://"
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Color(red: 0.067, green: 0.067, blue: 0.067)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Moon icon
                Image(systemName: "moon.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.8))

                Text("noisey")
                    .font(.largeTitle.weight(.thin))
                    .foregroundStyle(.white)

                Text("enter your server address")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    TextField("http://192.168.1.100:8080", text: $urlText)
                        .textFieldStyle(.plain)
                        .font(.body.monospaced())
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        connect()
                    } label: {
                        Group {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("connect")
                                    .font(.body.weight(.medium))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.15))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isConnecting)
                }
                .padding(.horizontal, 40)

                Spacer()
                Spacer()
            }
        }
    }

    private func connect() {
        guard let url = URL(string: urlText) else {
            error = "invalid URL"
            return
        }
        error = nil
        isConnecting = true

        Task {
            // Test the connection directly before committing
            let client = NoiseyClient(baseURL: url)
            do {
                _ = try await client.status()
                store.serverURL = urlText
                store.connect()
            } catch {
                self.error = "could not reach server"
            }
            isConnecting = false
        }
    }
}
