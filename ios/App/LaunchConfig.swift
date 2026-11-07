import Foundation

/// Mac からサービストークンを流し込む入口（nobu-ios と同じ作り。iPhone で長い文字列を打たずに済ませる）。
/// ⚠️ シークレットはソースに含めない。値は外から渡し、Keychain へ移す:
///
/// 1. ファイル（推奨）: `devicectl device copy to` / `simctl` でアプリのコンテナの tmp/ に
///    `kk-import-access-client-id` と `kk-import-access-client-secret` を置くと、次の起動で Keychain へ移して**即削除**
/// 2. 起動引数: `-kkAccessId <id> -kkAccessSecret <secret>`（手元のテスト用）
/// 3. 設定画面の欄に貼る（家族の iPhone はこれ）
enum LaunchConfig {
    static func applyIfPresent() {
        let fm = FileManager.default
        let items: [(String, KeychainSecret)] = [
            ("kk-import-access-client-id", AccessTokenStore.clientID),
            ("kk-import-access-client-secret", AccessTokenStore.clientSecret),
        ]
        for (name, secret) in items {
            let url = fm.temporaryDirectory.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { continue }
            defer { try? fm.removeItem(at: url) }
            if let data = try? Data(contentsOf: url) {
                let v = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { try? secret.save(v) }
            }
        }
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.index(after: i) < args.endIndex else { return nil }
            let v = args[args.index(after: i)]
            return v.hasPrefix("-") ? nil : v
        }
        if let id = value(after: "-kkAccessId") { try? AccessTokenStore.clientID.save(id) }
        if let s = value(after: "-kkAccessSecret") { try? AccessTokenStore.clientSecret.save(s) }
        #if DEBUG
        if let m = value(after: "-kkMember") { SharedStore.member = m }
        #endif
    }
}
