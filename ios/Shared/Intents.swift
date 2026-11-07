import AppIntents
import WidgetKit

/// ウィジェットの ○ ボタン（アプリを開かずに ✓）。アプリとウィジェット拡張の両方に入れる
struct ToggleItemIntent: AppIntent {
    static let title: LocalizedStringResource = "済み／まだを切り替える"
    static let isDiscoverable = false

    @Parameter(title: "項目")
    var itemID: Int

    init() {}
    init(itemID: Int) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        guard let member = SharedStore.member else { throw APIError.noMember }
        // 先に手元を ✓ にしておく（描き直しで即座に見える）。通信に失敗したら元に戻す
        let before = SharedStore.lastBoard
        if let before { SharedStore.lastBoard = before.toggled(id: itemID, by: member, at: Date()) }
        do {
            _ = try await BoardAPI.shared.toggle(id: itemID, by: member)
        } catch {
            SharedStore.lastBoard = before
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

enum ItemKindAppEnum: String, AppEnum {
    case need
    case daily

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "種類"
    static let caseDisplayRepresentations: [ItemKindAppEnum: DisplayRepresentation] = [
        .need: "必要なもの",
        .daily: "毎日のこと",
    ]

    var kind: ItemKind { self == .need ? .need : .daily }
}

/// Siri・ショートカットから足す。既定は「必要なもの」
struct AddItemIntent: AppIntent {
    static let title: LocalizedStringResource = "家族掲示板に足す"
    static let description = IntentDescription("家族掲示板の「必要なもの」（または「毎日のこと」）に足します")
    static let openAppWhenRun = false

    @Parameter(title: "足すもの", requestValueDialog: IntentDialog("何を足しますか？"))
    var title: String

    @Parameter(title: "種類", default: .need)
    var kind: ItemKindAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$title) を \(\.$kind) に足す")
    }

    init() {}
    init(title: String, kind: ItemKindAppEnum = .need) {
        self.title = title
        self.kind = kind
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let member = SharedStore.member else { throw APIError.noMember }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw $title.needsValueError("何を足しますか？") }
        _ = try await BoardAPI.shared.add(kind: kind.kind, title: t, by: member)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "「\(t)」を\(kind.kind.label)に足しました")
    }
}
