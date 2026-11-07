import AppIntents

/// Siri の言い方。App Shortcuts の言い回しには自由な文字列を埋め込めない（AppEntity／AppEnum だけ）ので、
/// 「家族掲示板に足して」→ Siri「何を足しますか？」→「玉ねぎ」の2段になる
struct KazokuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddItemIntent(),
            phrases: [
                "\(.applicationName)に足して",
                "\(.applicationName)に追加",
                "\(.applicationName)に足す",
                "\(.applicationName)の\(\.$kind)に足して",
            ],
            shortTitle: "家族掲示板に足す",
            systemImageName: "plus.circle"
        )
    }
}
