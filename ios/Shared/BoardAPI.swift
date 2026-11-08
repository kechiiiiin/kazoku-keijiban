import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case noMember
    case unauthorized
    case http(Int, String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "サービストークンが入っていません（設定）"
        case .noMember: return "この iPhone が誰のものか、まだ選ばれていません"
        case .unauthorized: return "Cloudflare Access を通れませんでした（サービストークンを確かめてください）"
        case .transport(let m): return "通信できませんでした（\(m)）"
        case .http(let code, let e):
            switch e {
            case "bad_title": return "書いた内容を確かめてください（60文字まで）"
            case "bad_kind": return "種類が正しくありません"
            case "bad_member": return "名前がボードの家族に入っていません"
            case "bad_reset_time": return "時刻が正しくありません"
            case "not_found": return "見つかりませんでした（もう消えたかもしれません）"
            default: return "エラー（\(code) \(e)）"
            }
        }
    }
}

/// つなぎ先
enum ServerConfig {
    /// 本番。Info.plist の KKServerURL（project.yml の KAZOKU_SERVER_URL から入る）
    static var productionURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "KKServerURL") as? String,
              let url = URL(string: s), url.host?.isEmpty == false else { return nil }
        return url
    }

    #if DEBUG
    private static let debugKey = "debugBaseURL"
    /// **DEBUG ビルドだけ**: シミュレータでローカルの Worker を見る。
    /// アプリの起動引数 `-kkBaseURL http://127.0.0.1:8791` を App Group に写し、ウィジェットも同じ先を見る
    static func applyLaunchOverride() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-kkBaseURL"), args.index(after: i) < args.endIndex {
            AppGroup.defaults.set(args[args.index(after: i)], forKey: debugKey)
        }
    }
    static var debugURL: URL? {
        guard let s = AppGroup.defaults.string(forKey: debugKey), let url = URL(string: s),
              let scheme = url.scheme, scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
    #endif

    static var baseURL: URL? {
        #if DEBUG
        if let u = debugURL { return u }
        #endif
        return productionURL
    }

    /// ローカルの Worker（認証を迂回する dev）に向いているか。DEBUG のときだけ true になりうる
    static var isLocalDev: Bool {
        #if DEBUG
        guard let host = debugURL?.host else { return false }
        return host == "127.0.0.1" || host == "localhost"
        #else
        return false
        #endif
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Access のログイン画面への 302 を追わない
    }
}

/// 家族掲示板の Worker を叩く。成功した一覧は App Group に残す（ウィジェットが読む）
final class BoardAPI: @unchecked Sendable {
    static let shared = BoardAPI()

    private let session: URLSession
    private let noRedirect = NoRedirect()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: config)
    }

    var isConfigured: Bool { ServerConfig.isLocalDev || (AccessTokenStore.isComplete && ServerConfig.baseURL != nil) }

    // MARK: - 口

    func board() async throws -> Board { try await call("GET", "/api/board") }

    func add(kind: ItemKind, title: String, by: String) async throws -> Board {
        try await call("POST", "/api/items", body: ["kind": kind.rawValue, "title": title, "by": by])
    }

    func toggle(id: Int, by: String) async throws -> Board {
        try await call("POST", "/api/items/\(id)/toggle", body: ["by": by])
    }

    func remove(id: Int) async throws -> Board { try await call("DELETE", "/api/items/\(id)") }

    func setResetTime(_ hhmm: String) async throws -> Board {
        try await call("PUT", "/api/settings/reset-time", body: ["reset_time": hhmm])
    }

    func registerDevice(token: String, member: String) async throws {
        _ = try await raw("PUT", "/api/devices", body: ["push_token": token, "member": member])
    }

    // MARK: - 下まわり

    private func call(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> Board {
        let data = try await raw(method, path, body: body)
        do {
            let b = try decoder.decode(Board.self, from: data)
            SharedStore.lastBoard = b
            return b
        } catch {
            throw APIError.transport("応答を読めませんでした")
        }
    }

    private func raw(_ method: String, _ path: String, body: [String: String]?) async throws -> Data {
        guard let base = ServerConfig.baseURL, let url = URL(string: path, relativeTo: base) else { throw APIError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !ServerConfig.isLocalDev {
            guard let id = AccessTokenStore.idValue, let secret = AccessTokenStore.secretValue else {
                throw APIError.notConfigured
            }
            req.setValue(id, forHTTPHeaderField: "CF-Access-Client-Id")
            req.setValue(secret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req, delegate: noRedirect)
        } catch {
            throw APIError.transport((error as NSError).localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("応答がありません") }
        if (300..<400).contains(http.statusCode) || http.statusCode == 401 || http.statusCode == 403 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let e = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "unknown"
            throw APIError.http(http.statusCode, e)
        }
        return data
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

/// ウィジェット用プッシュのトークンを、この iPhone の名前と一緒にサーバーへ登録する（同じ組なら省く）
enum PushRegistration {
    static func registerIfNeeded(force: Bool = false) async {
        guard let token = SharedStore.widgetPushToken, let member = SharedStore.member else { return }
        let key = "\(token)/\(member)"
        if !force, SharedStore.registeredPush == key { return }
        do {
            try await BoardAPI.shared.registerDevice(token: token, member: member)
            SharedStore.registeredPush = key
        } catch {
            // 次の起動・次のトークン変化でまた試す
        }
    }
}
