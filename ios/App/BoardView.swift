import SwiftUI

struct BoardView: View {
    @Environment(AppModel.self) private var model
    @State private var newTitle = ""
    @State private var kind: ItemKind = .need
    @State private var showSettings = false
    @FocusState private var focused: Bool

    var body: some View {
        let board = model.board ?? .empty
        List {
            Text("\(model.member ?? "")の iPhone・毎日のことは \(board.resetTime) に戻ります")
                .font(.caption).foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            if let e = model.errorMessage {
                Section { Text(e).font(.footnote).foregroundStyle(.red) }
            }
            Section {
                if board.daily.isEmpty { Text("まだありません").foregroundStyle(.secondary) }
                ForEach(board.daily) { row($0) }
            } header: {
                Text("毎日のこと \(board.dailyDoneCount)/\(board.daily.count)")
            }
            Section("必要なもの") {
                if board.needs.isEmpty { Text("まだありません").foregroundStyle(.secondary) }
                ForEach(board.needs) { row($0) }
            }
            Section {
                addBox
            } footer: {
                Text("Siri：「家族掲示板に足して」→「何を足しますか？」に「玉ねぎ」と答えると「必要なもの」に入ります。毎日のことは「家族掲示板の毎日のことに足して」。")
            }
        }
        .navigationTitle("家族掲示板")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("設定")
            }
        }
        .refreshable { await model.load() }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView(firstRun: false) } }
    }

    private func row(_ item: BoardItem) -> some View {
        Button { Task { await model.toggle(item) } } label: {
            HStack(spacing: 12) {
                Image(systemName: item.done == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(item.done == nil ? Color.secondary : Color.green)
                Text(item.title).foregroundStyle(item.done == nil ? .primary : .secondary)
                Spacer()
                if let by = item.done?.by {
                    Text(by).font(.caption.weight(.semibold)).foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) { Task { await model.remove(item) } } label: { Label("外す", systemImage: "trash") }
        }
        .accessibilityIdentifier("row-\(item.id)")
    }

    @ViewBuilder
    private var addBox: some View {
        Group {
            // ⚠️ Return（日本語変換の確定を含む）では足さない。足すのは「足す」ボタンだけ。
            //    onSubmit を付けないので、Return はキーボードを閉じるだけ
            TextField("思いついたものを書く（例：玉ねぎ）", text: $newTitle)
                .submitLabel(.done)
                .focused($focused)
                .accessibilityIdentifier("newTitle")
            Picker("種類", selection: $kind) {
                ForEach(ItemKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                let t = newTitle
                Task {
                    if await model.add(kind: kind, title: t) {
                        newTitle = ""
                        focused = false
                    }
                }
            } label: {
                Text("足す").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("addButton")
        }
    }
}
