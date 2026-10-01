import Foundation

enum Config {
    /// The web app. Both apps read and write the same board through it, so an
    /// edit in either one is what the other opens on.
    static let appBaseURL: String = {
        let env = ProcessInfo.processInfo.environment["QUICK_STICK_URL"] ?? ""
        return env.isEmpty ? "http://localhost:4445" : env
    }()
    static let boardPath = "/api/board"

    /// The same web app on this machine's LAN address, for a phone to open.
    /// Nil when there is no LAN interface up.
    static var lanURL: String? {
        guard let ip = lanAddress() else { return nil }
        let port = URL(string: appBaseURL)?.port ?? 4445
        return "http://\(ip):\(port)"
    }

    private static func lanAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: p.pointee.ifa_name)
            guard name.hasPrefix("en"), p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(p.pointee.ifa_addr, socklen_t(p.pointee.ifa_addr.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if found == nil { found = ip }
            if name == "en0" { return ip }
        }
        return found
    }
}
