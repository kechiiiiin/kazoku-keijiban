import SwiftUI
import WidgetKit

struct BoardEntry: TimelineEntry {
    let date: Date
    let board: Board?
    let member: String?
}

struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: Date(), board: .sample, member: "A")
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        if context.isPreview {
            completion(BoardEntry(date: Date(), board: .sample, member: "A"))
            return
        }
        completion(BoardEntry(date: Date(), board: SharedStore.lastBoard?.rolledOver(at: Date()), member: SharedStore.member))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        Task {
            let now = Date()
            var board = SharedStore.lastBoard
            if BoardAPI.shared.isConfigured, let fresh = try? await BoardAPI.shared.board() {
                board = fresh
            }
            board = board?.rolledOver(at: now)
            let member = SharedStore.member
            var entries = [BoardEntry(date: now, board: board, member: member)]
            // 戻り時刻ちょうどに描き直す（通信できなくても、手元で次の日に進めた一覧を出す）
            let reset = board?.nextReset
            if let board, let reset, reset > now {
                entries.append(BoardEntry(date: reset, board: board.rolledOver(at: reset), member: member))
            }
            let next = min(reset ?? now.addingTimeInterval(3600), now.addingTimeInterval(3600))
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }
}

/// iOS 26 のウィジェット用プッシュ。トークンが変わったら名前と一緒にサーバーへ登録する
struct BoardPushHandler: WidgetPushHandler {
    init() {}

    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        SharedStore.widgetPushToken = pushInfo.token.hexString
        Task { await PushRegistration.registerIfNeeded() }
    }
}

struct BoardWidget: Widget {
    static let kind = "BoardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BoardProvider()) { entry in
            BoardWidgetView(board: entry.board, member: entry.member)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("家族掲示板")
        .description("毎日のことと必要なもの。○ を押すとその場で ✓")
        .supportedFamilies([.systemLarge])
        .pushHandler(BoardPushHandler.self)
    }
}

@main
struct KazokuKeijibanWidgetBundle: WidgetBundle {
    var body: some Widget {
        BoardWidget()
    }
}

#Preview(as: .systemLarge) {
    BoardWidget()
} timeline: {
    BoardEntry(date: .now, board: .sample, member: "A")
}
