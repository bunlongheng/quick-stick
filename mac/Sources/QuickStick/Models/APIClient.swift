import Foundation

enum APIError: LocalizedError {
    case badStatus(Int)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "server \(code)"
        case .unreachable: return "web app unreachable"
        }
    }
}

/// One slot of the board as the web app's route handler stores it.
struct BoardCell: Codable, Sendable {
    let slot: Int
    let title: String
    let content: String
    let color: String
}

/// Talks to the web app's board route. The board is the whole set of 12
/// slots, read and written in one go - the same shape the web page uses.
struct APIClient {
    /// Names this launch, so its own writes are told apart from everyone else's
    /// when they come back down the stream.
    let client = UUID().uuidString

    private func request(_ method: String, path: String = Config.boardPath) throws -> URLRequest {
        guard let url = URL(string: Config.appBaseURL + path) else { throw APIError.unreachable }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.unreachable
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.badStatus(code) }
        return data
    }

    func board() async throws -> [BoardCell] {
        struct Reply: Decodable { let cells: [BoardCell] }
        let data = try await send(try request("GET"))
        return try JSONDecoder().decode(Reply.self, from: data).cells
    }

    func put(_ cells: [BoardCell]) async throws {
        struct Body: Encodable { let cells: [BoardCell]; let client: String }
        var req = try request("PUT")
        req.httpBody = try JSONEncoder().encode(Body(cells: cells, client: client))
        _ = try await send(req)
    }

    /// Every board written by anyone, as it happens. Returns when the
    /// connection drops; the caller decides whether to come back.
    func events(_ onEvent: @escaping @Sendable (BoardEvent) async -> Void) async throws {
        var req = try request("GET", path: Config.boardPath + "/stream")
        req.timeoutInterval = 120  // the server pings every 15 s
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.unreachable }
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            guard let event = try? JSONDecoder().decode(BoardEvent.self, from: Data(line.dropFirst(6).utf8)) else { continue }
            await onEvent(event)
        }
    }
}

struct BoardEvent: Decodable, Sendable {
    let client: String?
    let cells: [BoardCell]
}
