import Foundation

/// Worker の GET /api/board の形（snake_case は decoder で変換する）
struct Board: Codable, Equatable {
    var boardDay: String
    var resetTime: String
    var nextResetAt: String
    var members: [String]
    var daily: [BoardItem]
    var needs: [BoardItem]

    static let empty = Board(boardDay: "", resetTime: "04:00", nextResetAt: "", members: [], daily: [], needs: [])

    var nextReset: Date? { ISO8601.parse(nextResetAt) }

    var dailyDoneCount: Int { daily.filter { $0.done != nil }.count }
}

struct BoardItem: Codable, Identifiable, Hashable {
    var id: Int
    var kind: ItemKind
    var title: String
    var createdBy: String
    var done: Done?
}

struct Done: Codable, Hashable {
    var by: String
    var at: String
}

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case daily
    case need

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "毎日のこと"
        case .need: return "必要なもの"
        }
    }
}

enum ISO8601 {
    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

extension Board {
    /// 通信できないまま戻り時刻を過ぎたとき、手元の一覧を「次の日」に進める。
    /// 毎日のことは ○ に戻し、✓ の付いた必要なものは消す（サーバーと同じ決まり）
    func rolledOver(at now: Date) -> Board {
        guard let reset = nextReset, now >= reset else { return self }
        var b = self
        b.daily = daily.map { var i = $0; i.done = nil; return i }
        b.needs = needs.filter { $0.done == nil }
        var next = reset
        while next <= now { next = next.addingTimeInterval(24 * 60 * 60) }
        let f = ISO8601DateFormatter()
        b.nextResetAt = f.string(from: next)
        return b
    }

    /// ○⇄✓ を手元で先に反映する（ウィジェットのボタンをすぐ ✓ に見せるため）
    func toggled(id: Int, by: String, at now: Date) -> Board {
        var b = self
        func flip(_ list: inout [BoardItem]) {
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].done = list[i].done == nil ? Done(by: by, at: ISO8601DateFormatter().string(from: now)) : nil
        }
        flip(&b.daily)
        flip(&b.needs)
        return b
    }
}
