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

    /// `AEGIS_PRIVATE=1` — seri numaraları gibi kimlik verilerini kaynağında
    /// maskeler. Paylaşılacak ekran görüntüsü üretirken kullanılır; görüntü
    /// üzerinde bulanıklaştırmadan daha güvenilirdir çünkü veri UI'a hiç girmez.
    nonisolated static let privacyMasked = ProcessInfo.processInfo.environment["AEGIS_PRIVATE"] == "1"

    nonisolated static let maskText = "••••••••••"

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

    /// Sayfa başına render yüksekliği. Sayfalar kaydırmalı ve 860 px'ten uzun;
    /// sabit tek yükseklik, uzun sayfaları ortasından kırpıyordu.
    private static func height(for section: SystemMonitor.Section) -> CGFloat {
        switch section {
        case .dashboard: return 860
        case .battery: return 1760
        case .performance: return 1560
        case .energy: return 1560
        case .storage: return 1240
        case .cleanup: return 1400
        case .startup: return 1200
        case .hardware: return 860
        }
    }

    private static func render(section: SystemMonitor.Section,
                               monitor: SystemMonitor,
                               cleanup: CleanupStore,
                               into directory: URL) {
        let pageHeight = height(for: section)
        let view = page(for: section)
            .environment(monitor)
            .environment(cleanup)
            .foregroundStyle(Theme.text)
            .frame(width: 1080, height: pageHeight)
            .background { AuroraBackground() }
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(width: 1080, height: pageHeight)
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
