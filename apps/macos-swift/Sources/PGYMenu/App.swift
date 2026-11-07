import SwiftUI

struct PGYMenuApp: App {
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            state.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPanelView()
                .environmentObject(appState)
        } label: {
            if appState.menuBarText.isEmpty {
                Image(nsImage: appState.menuBarIcon)
                    .accessibilityLabel("随身 WiFi 信号")
            } else {
                HStack(spacing: 3) {
                    Image(nsImage: appState.menuBarIcon)
                    Text(appState.menuBarText)
                }
                .accessibilityLabel("随身 WiFi 信号")
            }
        }
        .menuBarExtraStyle(.window)

        Window("PGY 随身 WiFi", id: "settings") {
            SettingsView()
                .environmentObject(appState)
        }
        .defaultSize(width: 900, height: 690)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
