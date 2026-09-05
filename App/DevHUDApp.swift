import SwiftUI

@main
struct DevHUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("devHUD", systemImage: "gauge.with.dots.needle.33percent") {
            Toggle("Keep Pill Visible", isOn: Binding(
                get: { !delegate.controller.state.autoHide },
                set: { delegate.controller.setAutoHide(!$0) }
            ))
            Toggle("Launch at Login", isOn: Binding(
                get: { delegate.controller.state.launchAtLogin },
                set: { delegate.controller.setLaunchAtLogin($0) }
            ))
            Menu("Dock") {
                Button("Left") { delegate.controller.setEdge(.left) }
                Button("Right") { delegate.controller.setEdge(.right) }
                Divider()
                Button("Reset Position") { delegate.controller.resetPlacement() }
            }
            Menu("Display") {
                ForEach(NSScreen.screens, id: \.localizedName) { screen in
                    Button(screen.localizedName) { delegate.controller.setScreen(name: screen.localizedName) }
                }
            }
            Button("Hide for 1 Hour") { delegate.controller.hideForAnHour() }
            Button("Show Now") { delegate.controller.unhide() }
            Button("Refresh Now") { delegate.controller.refresh() }
                .keyboardShortcut("r")
            Divider()
            Button("Quit devHUD") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = HUDController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}
