import Foundation
import Security

/// アプリとウィジェット拡張で共有するもの（App Group）。
/// - UserDefaults（App Group）: この iPhone の名前・最後の一覧・ウィジェット用プッシュのトークン
/// - Keychain（App Group をアクセスグループに）: Access のサービストークン。**ソースにも UserDefaults にも置かない**
enum AppGroup {
    static let id = "group.jp.kechiiiiin.kazoku-keijiban"
    static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard
}

enum SharedStore {
    private static let memberKey = "member"
    private static let boardKey = "lastBoard"
    private static let pushTokenKey = "widgetPushToken"
    private static let registeredKey = "registeredPush"

    static var member: String? {
        get { AppGroup.defaults.string(forKey: memberKey) }
        set { AppGroup.defaults.set(newValue, forKey: memberKey) }
    }

    static var lastBoard: Board? {
        get {
            guard let data = AppGroup.defaults.data(forKey: boardKey) else { return nil }
            return try? JSONDecoder().decode(Board.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                AppGroup.defaults.set(data, forKey: boardKey)
            } else {
                AppGroup.defaults.removeObject(forKey: boardKey)
            }
        }
    }

    /// WidgetPushHandler から受けたトークン（16進）
    static var widgetPushToken: String? {
        get { AppGroup.defaults.string(forKey: pushTokenKey) }
        set { AppGroup.defaults.set(newValue, forKey: pushTokenKey) }
    }

    /// 最後にサーバーへ登録した「トークン/名前」。同じなら登録し直さない
    static var registeredPush: String? {
        get { AppGroup.defaults.string(forKey: registeredKey) }
        set { AppGroup.defaults.set(newValue, forKey: registeredKey) }
    }
}

/// Keychain の汎用パスワード1項目（nobu-ios と同じ作り）。App Group をアクセスグループにしてウィジェットからも読む。
/// アクセシビリティは AfterFirstUnlockThisDeviceOnly（ウィジェット・Siri がロック中でも読める・バックアップに乗らない）
struct KeychainSecret {
    private static let service = "jp.kechiiiiin.kazoku-keijiban"
    let account: String

    private func base(group: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        if group { q[kSecAttrAccessGroup as String] = AppGroup.id }
        return q
    }

    func save(_ value: String) throws {
        SecItemDelete(base(group: true) as CFDictionary)
        SecItemDelete(base(group: false) as CFDictionary)
        guard !value.isEmpty else { return } // 空文字は削除
        var add = base(group: true)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            // 署名なしのシミュレータ向けビルドなど、アクセスグループの entitlement が無いとき
            add.removeValue(forKey: kSecAttrAccessGroup as String)
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain への保存に失敗 (status=\(status))"])
        }
    }

    func load() -> String? {
        for group in [true, false] {
            var q = base(group: group)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    var isStored: Bool { load() != nil }
}

/// Cloudflare Access のサービストークン（`CF-Access-Client-Id` / `CF-Access-Client-Secret`）
enum AccessTokenStore {
    static let clientID = KeychainSecret(account: "cf-access-client-id")
    static let clientSecret = KeychainSecret(account: "cf-access-client-secret")

    static var isComplete: Bool { clientID.isStored && clientSecret.isStored }

    /// 画面に出してよい手がかり（Client ID の先頭だけ。シークレットは出さない）
    static var hint: String? {
        guard let id = clientID.load() else { return nil }
        return String(id.prefix(8)) + "…"
    }
}
