import SwiftUI
import AppKit

@main
struct AegisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var monitor = SystemMonitor()

    /// Karşılama ekranı bir kez gösterilir; Yardım menüsünden geri çağrılabilir.
    @AppStorage("welcomeCompleted") private var welcomeCompleted = false

    init() {
        // Öz denetim AppKit başlamadan koşar ve çıkar: WindowServer gerekmez.
        // Böylece Homebrew'un test sandbox'ı ve headless CI'da da anında biter.
        if SafetyGuardSelfTest.isRequested {
            exit(SafetyGuardSelfTest.run() == 0 ? 0 : 1)
        }
    }

    /// Snapshot modunda karşılama açılmaz — sekme görüntülerinin önünü kapatır.
    private var showWelcome: Binding<Bool> {
        Binding(
            get: { !welcomeCompleted && !Snapshot.isRendering },
            set: { if !$0 { welcomeCompleted = true } }
        )
    }

    var body: some Scene {
        Window("Aegis", id: "aegis-main") {
            RootView()
                .environment(monitor)
                .frame(minWidth: 1040, minHeight: 700)
                .background(AuroraBackground())
                .onAppear {
                    monitor.start()
                    Snapshot.runIfRequested(monitor: monitor)
                }
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.occlusionChanged)) { note in
                    let visible = (note.object as? Bool) ?? true
                    monitor.setActive(visible)
                }
                .sheet(isPresented: showWelcome) {
                    WelcomeView { welcomeCompleted = true }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                Button("Yenile") { monitor.refreshProcesses(); monitor.refreshVolumes() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .help) {
                Divider()
                Button("Hoş Geldin Ekranını Göster") { welcomeCompleted = false }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let occlusionChanged = Notification.Name("aegis.occlusion.changed")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Pencere tamamen örtüldüğünde örneklemeyi durdurmak için sinyal üretir.
    func applicationDidChangeOcclusionState(_ notification: Notification) {
        let visible = NSApp.occlusionState.contains(.visible)
        NotificationCenter.default.post(name: Self.occlusionChanged, object: visible)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
