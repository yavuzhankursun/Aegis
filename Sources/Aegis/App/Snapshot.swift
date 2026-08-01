import SwiftUI
import AppKit

/// Geliştirme aracı: `AEGIS_SNAPSHOT=/klasör` ile açılışta her sayfayı PNG'ye basar.
/// Normal çalıştırmada hiçbir şey yapmaz.
@MainActor
enum Snapshot {

    static var requestedDirectory: String? {
        ProcessInfo.processInfo.environment["AEGIS_SNAPSHOT"]
    }

    nonisolated static let isRendering = ProcessInfo.processInfo.environment["AEGIS_SNAPSHOT"] != nil

    static func runIfRequested(monitor: SystemMonitor) {
        guard let directory = requestedDirectory else { return }
        let url = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        Task {
            monitor.start()
            monitor.refreshProcesses()
            monitor.scanStorageCategories()
            try? await Task.sleep(for: .seconds(9))

            let cleanup = CleanupStore()
            cleanup.scan()
            try? await Task.sleep(for: .seconds(20))

            renderProbe(into: url)

            for section in SystemMonitor.Section.allCases {
                monitor.activeSection = section
                try? await Task.sleep(for: .seconds(1))
                render(section: section, monitor: monitor, cleanup: cleanup, into: url)
            }
            NSApp.terminate(nil)
        }
    }

    private static func renderProbe(into directory: URL) {
        let probe = VStack {
            Text("PROBE").font(.system(size: 60, weight: .bold)).foregroundStyle(Theme.text)
            GlassCard { Text("cam kart").foregroundStyle(Theme.text) }
        }
        .frame(width: 600, height: 300)
        .background(Color.black)

        let renderer = ImageRenderer(content: probe)
        renderer.scale = 1
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: directory.appendingPathComponent("00-probe.png"))
        }
    }

    private static func render(section: SystemMonitor.Section,
                               monitor: SystemMonitor,
                               cleanup: CleanupStore,
                               into directory: URL) {
        let view = page(for: section)
            .environment(monitor)
            .environment(cleanup)
            .foregroundStyle(Theme.text)
            .frame(width: 1080, height: 860)
            .background { AuroraBackground() }
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 860)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: directory.appendingPathComponent("\(section.symbol)-\(section.rawValue).png"))
    }

    @ViewBuilder
    private static func page(for section: SystemMonitor.Section) -> some View {
        switch section {
        case .dashboard:   DashboardView()
        case .battery:     BatteryView()
        case .performance: PerformanceView()
        case .energy:      EnergyView()
        case .storage:     StorageView()
        case .cleanup:     CleanupView()
        case .startup:     StartupView()
        case .hardware:    HardwareView()
        }
    }
}
