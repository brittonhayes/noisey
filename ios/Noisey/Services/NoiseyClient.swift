import Foundation

struct NoiseyClient: Sendable {
    let baseURL: URL

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: - Status

    func status() async throws -> StatusResponse {
        let (data, _) = try await URLSession.shared.data(from: url("api/status"))
        return try Self.decoder.decode(StatusResponse.self, from: data)
    }

    // MARK: - Sounds

    func sounds() async throws -> [SoundEntry] {
        let (data, _) = try await URLSession.shared.data(from: url("api/sounds"))
        return try Self.decoder.decode([SoundEntry].self, from: data)
    }

    func toggleSound(id: String) async throws -> StatusResponse {
        var request = URLRequest(url: url("api/sounds/\(id)/toggle"))
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.decoder.decode(StatusResponse.self, from: data)
    }

    func deleteSound(id: String) async throws -> StatusResponse {
        var request = URLRequest(url: url("api/sounds/\(id)"))
        request.httpMethod = "DELETE"
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.decoder.decode(StatusResponse.self, from: data)
    }

    // MARK: - Volume

    func setVolume(_ volume: Float) async throws -> StatusResponse {
        let body = ["volume": volume]
        return try await post("api/volume", body: body)
    }

    // MARK: - Sleep Timer

    func setSleepTimer(minutes: Int) async throws -> StatusResponse {
        let body = ["minutes": minutes]
        return try await post("api/sleep-timer", body: body)
    }

    // MARK: - Schedule

    func getSchedule() async throws -> Schedule? {
        let (data, _) = try await URLSession.shared.data(from: url("api/schedule"))
        return try Self.decoder.decode(Schedule?.self, from: data)
    }

    func setSchedule(_ schedule: Schedule) async throws -> StatusResponse {
        return try await post("api/schedule", body: schedule)
    }

    func deleteSchedule() async throws -> StatusResponse {
        var request = URLRequest(url: url("api/schedule"))
        request.httpMethod = "DELETE"
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.decoder.decode(StatusResponse.self, from: data)
    }

    // MARK: - Upload

    func uploadSound(fileURL: URL, name: String?, description: String?) async throws -> SoundEntry {
        let boundary = UUID().uuidString
        var request = URLRequest(url: url("api/sounds/upload"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // File part
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")

        // Optional text fields
        if let name {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n")
            body.append(name)
            body.append("\r\n")
        }
        if let description {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n")
            body.append(description)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.decoder.decode(SoundEntry.self, from: data)
    }

    // MARK: - Helpers

    private func url(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func post<T: Encodable>(_ path: String, body: T) async throws -> StatusResponse {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.decoder.decode(StatusResponse.self, from: data)
    }
}

// MARK: - Data helpers for multipart

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
