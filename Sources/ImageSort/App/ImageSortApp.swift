import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nødvendig når appen kjøres med `swift run` uten .app-pakke.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        AnalysisCache.shared.save()
    }
}

@main
struct ImageSortApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = LibraryViewModel()

    init() { Settings.register() }

    var body: some Scene {
        Window("ImageSort", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Åpne mappe …") { model.chooseFolder() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Angre siste sletting") { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo)
            }
        }

        SwiftUI.Settings {
            SettingsView()
        }
    }
}
