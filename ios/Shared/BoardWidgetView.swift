import SwiftUI
import WidgetKit
import AppIntents

/// ウィジェット（大）の中身。アプリの DEBUG 用プレビュー画面からも同じものを描く
struct BoardWidgetView: View {
    let board: Board?
    let member: String?

    var body: some View {
        if member == nil || board == nil {
            VStack(alignment: .leading, spacing: 8) {
                header(done: nil)
                Spacer()
                Text(member == nil ? "アプリを開いて、この iPhone が誰のものか選んでください" : "アプリを開いて一覧を読み込んでください")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else if let board {
            content(WidgetLayout(board: board))
        }
    }

    private func header(done: (Int, Int)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("家族掲示板").font(.headline)
            Spacer()
            if let done, done.1 > 0 {
                Text("毎日のこと \(done.0)/\(done.1)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(_ l: WidgetLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(done: (l.dailyDone, l.dailyTotal)).padding(.bottom, 6)
            if l.dailyTotal == 0 && l.needs.isEmpty {
                Spacer()
                Text("まだ何もありません。アプリで足してください").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(l.pendingDaily) { item in row(item) }
            if let s = l.doneSummary {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(s).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                .frame(height: 30)
            }
            if !l.needs.isEmpty {
                Text("必要なもの")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: 22, alignment: .bottom)
                ForEach(l.needs) { item in row(item) }
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ item: BoardItem) -> some View {
        Button(intent: ToggleItemIntent(itemID: item.id)) {
            HStack(spacing: 8) {
                Image(systemName: item.done == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(item.done == nil ? Color.secondary : Color.green)
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(item.done == nil ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let by = item.done?.by {
                    Text(by).font(.caption.weight(.semibold)).foregroundStyle(.green)
                }
            }
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension Board {
    /// プレビュー・プレースホルダー用（実在の家族の名前は使わない）
    static let sample = Board(
        boardDay: "2026-11-07", resetTime: "04:00", nextResetAt: "2026-11-07T19:00:00Z",
        members: ["A", "B", "C", "D"],
        daily: [
            BoardItem(id: 1, kind: .daily, title: "風呂掃除", createdBy: "A", done: Done(by: "C", at: "")),
            BoardItem(id: 2, kind: .daily, title: "弁当箱を出す（上）", createdBy: "A", done: nil),
            BoardItem(id: 3, kind: .daily, title: "弁当箱を出す（下）", createdBy: "A", done: Done(by: "D", at: "")),
            BoardItem(id: 4, kind: .daily, title: "洗濯物たたむ", createdBy: "B", done: nil),
        ],
        needs: [
            BoardItem(id: 5, kind: .need, title: "玉ねぎ", createdBy: "B", done: nil),
            BoardItem(id: 6, kind: .need, title: "単4電池", createdBy: "A", done: Done(by: "B", at: "")),
            BoardItem(id: 7, kind: .need, title: "体操服の名札", createdBy: "B", done: nil),
        ])
}
