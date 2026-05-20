import Foundation

enum APIError: LocalizedError {
    case invalidCredentials
    case notAuthenticated
    case http(Int, String?)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Wrong username or password."
        case .notAuthenticated:   return "You're signed out. Sign in again."
        case .http(let code, let msg): return "Server returned \(code)\(msg.map { ": \($0)" } ?? "")."
        case .decoding(let msg):  return "Couldn't read server response: \(msg)"
        case .network(let msg):   return "Can't reach the server: \(msg)"
        }
    }
}

nonisolated struct Specs: Codable, Sendable {
    let os: OS
    let cpu: CPU
    let memory: Memory
    let disks: [Disk]
    let network: [Network]
    let uptimeSeconds: Double

    struct OS: Codable {
        let distro: String?
        let release: String?
        let kernel: String?
        let arch: String?
        let hostname: String?
    }
    struct CPU: Codable {
        let manufacturer: String?
        let brand: String?
        let cores: Int?
        let physicalCores: Int?
        let speed: Double?
        let load: Double?
        let tempC: Double?
    }
    struct Memory: Codable {
        let total: Int64?
        let used: Int64?
        let free: Int64?
        let swapTotal: Int64?
        let swapUsed: Int64?
    }
    struct Disk: Codable {
        let fs: String?
        let type: String?
        let size: Int64?
        let used: Int64?
        let available: Int64?
        let use: Double?
        let mount: String?
    }
    struct Network: Codable {
        let iface: String?
        let ip4: String?
        let mac: String?
        let speed: Double?
    }
}

nonisolated struct ServersResponse: Codable, Sendable {
    let servers: [Service]
}

nonisolated struct FileListing: Codable, Sendable {
    let root: String
    let currentRel: String
    let parentRel: String?
    let items: [FileEntry]
}

nonisolated struct FileEntry: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let rel: String
    let isDir: Bool
    let isSymlink: Bool
    let size: Int64?
    let mtime: Date?

    var id: String { rel }
}

nonisolated struct Service: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: String
    let description: String
    let endpoints: [Endpoint]
    let status: String
    let controllable: Bool

    struct Endpoint: Codable, Hashable, Sendable {
        let label: String
        let url: String
    }
}

final class HomeDashAPI: NSObject, URLSessionTaskDelegate {
    static let shared = HomeDashAPI()
    static let defaultBaseURL = "http://192.168.68.98:3030"
    static let serverURLKey = "serverURL"

    var baseURL: URL {
        let raw = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? Self.defaultBaseURL
        return URL(string: raw) ?? URL(string: Self.defaultBaseURL)!
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // Don't auto-follow redirects: we need to see the 302 on login success,
    // and we don't want protected endpoints to silently redirect to /login.
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func login(username: String, password: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("login"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "username=\(formEncode(username))&password=\(formEncode(password))"
            .data(using: .utf8)

        let (_, response) = try await sendRequest(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.network("No response.") }
        switch http.statusCode {
        case 302: return
        case 401: throw APIError.invalidCredentials
        default:  throw APIError.http(http.statusCode, nil)
        }
    }

    func logout() async {
        var req = URLRequest(url: baseURL.appendingPathComponent("logout"))
        req.httpMethod = "POST"
        _ = try? await sendRequest(req)
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
            for c in cookies { HTTPCookieStorage.shared.deleteCookie(c) }
        }
    }

    func isLoggedIn() -> Bool {
        let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        return cookies.contains(where: { $0.name == "hsd.sid" })
    }

    func specs() async throws -> Specs {
        try await getJSON("/api/specs", as: Specs.self)
    }

    func servers() async throws -> [Service] {
        let r: ServersResponse = try await getJSON("/servers/api/status", as: ServersResponse.self)
        return r.servers
    }

    func listFiles(path: String, showHidden: Bool = false) async throws -> FileListing {
        var comps = URLComponents(url: baseURL.appendingPathComponent("files/api/list"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "showHidden", value: showHidden ? "1" : "0"),
        ]
        let req = URLRequest(url: comps.url!)
        let (data, response) = try await sendRequest(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.network("No response.") }
        if http.statusCode == 302 || http.statusCode == 401 { throw APIError.notAuthenticated }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode, nil) }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(FileListing.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    func downloadURL(for path: String) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent("files/download"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "path", value: path)]
        return comps.url!
    }

    func download(path: String) async throws -> URL {
        let req = URLRequest(url: downloadURL(for: path))
        let (data, response) = try await sendRequest(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.network("No response.") }
        if http.statusCode == 302 || http.statusCode == 401 { throw APIError.notAuthenticated }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode, nil) }
        let name = (path as NSString).lastPathComponent.isEmpty ? "download" : (path as NSString).lastPathComponent
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        try data.write(to: dest)
        return dest
    }

    func control(serviceID: String, action: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("servers/\(serviceID)/\(action)"))
        req.httpMethod = "POST"
        let (data, response) = try await sendRequest(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.network("No response.") }
        switch http.statusCode {
        case 200: return
        case 302, 401: throw APIError.notAuthenticated
        default:
            let msg = String(data: data, encoding: .utf8)
            throw APIError.http(http.statusCode, msg)
        }
    }

    private func getJSON<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await sendRequest(URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { throw APIError.network("No response.") }
        if http.statusCode == 302 || http.statusCode == 401 { throw APIError.notAuthenticated }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode, nil) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func sendRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func formEncode(_ s: String) -> String {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&+=")
        return s.addingPercentEncoding(withAllowedCharacters: cs) ?? s
    }
}
