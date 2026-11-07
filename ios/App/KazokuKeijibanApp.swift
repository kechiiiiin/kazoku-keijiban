import SwiftUI
import WidgetKit

@main
struct KazokuKeijibanApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        ServerConfig.applyLaunchOverride()
        #endif
        LaunchConfig.applyIfPresent()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
