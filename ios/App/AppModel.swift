import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class AppModel {
    var board: Board? = SharedStore.lastBoard
    var member: String? = SharedStore.member
    var errorMessage: String?
    var isLoading = false
    var isConfigured = BoardAPI.shared.isConfigured

    private let api = BoardAPI.shared

    func setMember(_ name: String) {
        SharedStore.member = name
        member = name
        WidgetCenter.shared.reloadAllTimelines()
        Task { await registerPush(force: true) }
    }

    func refreshConfigured() {
        isConfigured = api.isConfigured
    }

    func load() async {
        refreshConfigured()
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        await run { try await self.api.board() }
        await registerPush()
    }

    func toggle(_ item: BoardItem) async {
        guard let member else { return }
        if let b = board { board = b.toggled(id: item.id, by: member, at: Date()) } // 先に見た目だけ
        await run { try await self.api.toggle(id: item.id, by: member) }
    }

    func add(kind: ItemKind, title: String) async -> Bool {
        guard let member else { return false }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return await run { try await self.api.add(kind: kind, title: t, by: member) }
    }

    func remove(_ item: BoardItem) async {
        await run { try await self.api.remove(id: item.id) }
    }

    func setResetTime(_ date: Date) async {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "Asia/Tokyo")!, from: date)
        let hhmm = String(format: "%02d:%02d", c.hour ?? 4, c.minute ?? 0)
        await run { try await self.api.setResetTime(hhmm) }
    }

    @discardableResult
    private func run(_ op: @escaping () async throws -> Board) async -> Bool {
        do {
            board = try await op()
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            errorMessage = error.localizedDescription
            board = SharedStore.lastBoard ?? board
            return false
        }
    }

    /// ウィジェット用プッシュのトークンを登録（アプリ側からも拾う。ウィジェットの PushHandler が先に動いていればそれを使う）
    func registerPush(force: Bool = false) async {
        if let info = await WidgetCenter.shared.currentPushInfo {
            SharedStore.widgetPushToken = info.token.hexString
        }
        await PushRegistration.registerIfNeeded(force: force)
    }
}
