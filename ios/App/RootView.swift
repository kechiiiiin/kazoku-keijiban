import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-kkWidgetPreview") {
                WidgetPreviewScreen()
            } else {
                main
            }
            #else
            main
            #endif
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    @ViewBuilder
    private var main: some View {
        if !model.isConfigured {
            NavigationStack { SettingsView(firstRun: true) }
        } else if model.member == nil {
            MemberPickView()
        } else {
            NavigationStack { BoardView() }
        }
    }
}

/// 初回に「この iPhone は誰のものか」を選ぶ
struct MemberPickView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("家族掲示板").font(.largeTitle.bold())
            Text("この iPhone は誰のものですか？\n○ を押したときに付く名前になります（あとで設定で変えられます）")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let members = model.board?.members, !members.isEmpty {
                VStack(spacing: 12) {
                    ForEach(members, id: \.self) { m in
                        Button { model.setMember(m) } label: {
                            Text(m).font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
                .padding(.horizontal, 40)
            } else if model.isLoading {
                ProgressView()
            } else {
                Text(model.errorMessage ?? "家族の名前を読み込めませんでした")
                    .font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("読み直す") { Task { await model.load() } }
            }
            Spacer()
            Spacer()
        }
        .padding()
    }
}
