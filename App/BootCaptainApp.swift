import SwiftUI

@main
struct BootCaptainApp: App {
    @StateObject private var scan = ScanViewModel()
    @StateObject private var helper = HelperClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scan)
                .environmentObject(helper)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    helper.refreshStatus()
                    scan.scan(diagnose: false)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Rescan") { scan.scan(diagnose: false) }
                    .keyboardShortcut("r")
                Button("Run Boot Audit") { scan.scan(diagnose: true) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
