import SwiftUI

struct SettingsView: View {
    let firstRun: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var resetDate: Date
    @State private var saved: String?

    init(firstRun: Bool) {
        self.firstRun = firstRun
        let hhmm = SharedStore.lastBoard?.resetTime ?? "04:00"
        _resetDate = State(initialValue: Self.date(from: hhmm) ?? Date())
    }

    var body: some View {
        Form {
            if !firstRun, let board = model.board {
                Section("この iPhone は") {
                    Picker("名前", selection: Binding(get: { model.member ?? "" }, set: { model.setMember($0) })) {
                        ForEach(board.members, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    DatePicker("毎日のことを戻す時刻", selection: $resetDate, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
                    Button("この時刻にする") { Task { await model.setResetTime(resetDate); saved = "戻り時刻を変えました" } }
                } footer: {
                    Text("いまは \(board.resetTime)。家族みんなに効きます")
                }
            }
            Section {
                TextField("Client ID", text: $clientID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Client Secret", text: $clientSecret)
                Button("保存") {
                    if !clientID.isEmpty { try? AccessTokenStore.clientID.save(clientID.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    if !clientSecret.isEmpty { try? AccessTokenStore.clientSecret.save(clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    clientID = ""
                    clientSecret = ""
                    saved = "保存しました"
                    model.refreshConfigured()
                    Task { await model.load() }
                }
                .disabled(clientID.isEmpty && clientSecret.isEmpty)
            } header: {
                Text("サービストークン（Cloudflare Access）")
            } footer: {
                Text(AccessTokenStore.hint.map { "入っています（\($0)）" } ?? "まだ入っていません。啓輔さんから受け取った値を貼ってください")
            }
            if let saved { Section { Text(saved).foregroundStyle(.secondary) } }
            if let e = model.errorMessage { Section { Text(e).font(.footnote).foregroundStyle(.red) } }
        }
        .navigationTitle(firstRun ? "はじめに" : "設定")
        .toolbar {
            if !firstRun {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }

    static func date(from hhmm: String) -> Date? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c.date(bySettingHour: p[0], minute: p[1], second: 0, of: Date())
    }
}

#if DEBUG
/// シミュレータでウィジェットの描画を確かめる画面（起動引数 -kkWidgetPreview）。
/// ホーム画面に置いたときと同じ BoardWidgetView を、大サイズの寸法で描く
struct WidgetPreviewScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.96, green: 0.79, blue: 0.6), Color(red: 0.62, green: 0.76, blue: 0.9)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 12) {
                BoardWidgetView(board: model.board ?? .sample, member: model.member ?? "A")
                    .padding(16)
                    .frame(width: 364, height: 382)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                Text(model.board == nil ? "（見本のデータ）" : "（サーバーの一覧）")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
#endif
