import Foundation

/// ウィジェット（大）の並び。設計どおり:
/// - 毎日のことを優先。**まだのもの**を上に1行ずつ
/// - 済んだ毎日のことは「済 3：風呂掃除 B・…」と**1行にまとめる**
/// - 必要なものは**余った行にだけ**出し、溢れた分は**何も残さない**（「ほか n 件」も出さない）
struct WidgetLayout: Equatable {
    var pendingDaily: [BoardItem]
    var doneSummary: String?
    var needs: [BoardItem]
    var dailyDone: Int
    var dailyTotal: Int

    /// 行の数（見出し「必要なもの」も1行に数える）。大サイズで文字が詰まりすぎない数
    static let capacity = 9

    init(board: Board, capacity: Int = WidgetLayout.capacity) {
        let pending = board.daily.filter { $0.done == nil }
        let done = board.daily.filter { $0.done != nil }
        dailyDone = done.count
        dailyTotal = board.daily.count

        let summaryLines = done.isEmpty ? 0 : 1
        let pendingShown = min(pending.count, max(0, capacity - summaryLines))
        pendingDaily = Array(pending.prefix(pendingShown))
        doneSummary = done.isEmpty ? nil : WidgetLayout.summary(done)

        // 余り。見出しの1行と、少なくとも1件が入るときだけ必要なものを出す
        let left = capacity - pendingShown - summaryLines
        if left >= 2 {
            // まだのものを先に（✓ は次の戻り時刻まで ✓ のまま残る）
            let ordered = board.needs.filter { $0.done == nil } + board.needs.filter { $0.done != nil }
            needs = Array(ordered.prefix(left - 1))
        } else {
            needs = []
        }
    }

    static func summary(_ done: [BoardItem]) -> String {
        "済 \(done.count)：" + done.map { "\($0.title) \($0.done?.by ?? "")" }.joined(separator: "・")
    }
}
