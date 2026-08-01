import SwiftUI

/// Performans sekmesi. Kartlar **ayrı `View`'lar**: her 2 saniyede bir gelen
/// telemetri yalnızca ilgili kartı geçersiz kılsın diye. Hepsi tek bir gövdede
/// olsaydı `cpuHistory`'nin her güncellemesi 45 süreci yeniden sıraladırır,
/// 10 satırlık listeyi ve dört cam yüzeyi baştan çizdirirdi.
struct PerformanceView: View {
    /// Yalnızca `quit()` içinde kullanılır — gövde hiçbir @Observable özelliği
    /// okumaz, dolayısıyla telemetri güncellemeleri bu görünümü geçersiz kılmaz.
    @Environment(SystemMonitor.self) private var monitor
    @State private var quitCandidate: ProcessInfoRow?
    @State private var lastAction: String?

    var body: some View {
        PageScaffold(
            title: "Performans",
            subtitle: "Bellek baskısı, işlemci yükü ve RAM'i en çok tüketen uygulamalar",
            symbol: "gauge.with.dots.needle.67percent",
            accent: Theme.steel,
            toolbar: AnyView(PressureBadge(lastAction: lastAction))
        ) {
            MemoryCard()
            CPUCard()
            MemoryHogsCard { quitCandidate = $0 }
            AdvisoryCard()
        }
        .alert("Uygulamayı kapat", isPresented: .init(
            get: { quitCandidate != nil },
            set: { if !$0 { quitCandidate = nil } }
        ), presenting: quitCandidate) { process in
            Button("Vazgeç", role: .cancel) { quitCandidate = nil }
            Button("Kapat", role: .destructive) { quit(process) }
        } message: { process in
            Text("\(process.name) uygulamasına kapatma isteği gönderilecek (Cmd+Q ile aynı). "
                 + "Kaydedilmemiş veri varsa uygulama sana soracak. Zorla sonlandırma yapılmaz.")
        }
    }

    @MainActor
    private func quit(_ process: ProcessInfoRow) {
        let outcome = ProcessTerminator.requestQuit(pid: process.pid)
        switch outcome {
        case .requested: lastAction = "\(process.name) kapatılıyor"
        case .notFound: lastAction = "Uygulama zaten kapanmış"
        case .notAllowed: lastAction = "Bu süreç kapatılamaz"
        }
        quitCandidate = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            monitor.refreshProcesses()
            try? await Task.sleep(for: .seconds(3))
            lastAction = nil
        }
    }
}

// MARK: - Başlık rozeti

private struct PressureBadge: View {
    @Environment(SystemMonitor.self) private var monitor
    let lastAction: String?

    var body: some View {
        let memory = monitor.memory
        return HStack(spacing: 8) {
            if let lastAction {
                Pill(text: lastAction, color: Theme.mint, symbol: "checkmark")
            }
            Pill(text: "Baskı: \(memory.pressureLevel.rawValue)",
                 color: Theme.color(forPressure: memory.pressureLevel),
                 symbol: "memorychip")
        }
    
    }
}

// MARK: - Bellek dağılımı

private struct MemoryCard: View {
    @Environment(SystemMonitor.self) private var monitor
    private var memory: MemorySnapshot { monitor.memory }

    var body: some View {
        GlassSection(title: "Bellek Dağılımı", symbol: "memorychip", accent: Theme.indigo) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 26) {
                    RingGauge(
                        fraction: memory.pressurePercent / 100,
                        gradient: Theme.gradient([Theme.color(forPressure: memory.pressureLevel),
                                                  Theme.color(forPressure: memory.pressureLevel).opacity(0.5)]),
                        lineWidth: 11
                    ) {
                        VStack(spacing: 0) {
                            Text("\(Int(memory.pressurePercent))%")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("baskı")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 92, height: 92)

                    VStack(alignment: .leading, spacing: 12) {
                        SegmentedBar(segments: [
                            .init(value: Double(memory.wiredBytes), color: Theme.coral, label: "Sistem"),
                            .init(value: Double(memory.appMemoryBytes), color: Theme.indigo, label: "Uygulama"),
                            .init(value: Double(memory.compressedBytes), color: Theme.violet, label: "Sıkıştırılmış"),
                            .init(value: Double(memory.inactiveBytes), color: Theme.aqua.opacity(0.7), label: "Etkin değil"),
                            .init(value: Double(memory.freeBytes), color: Theme.mint.opacity(0.45), label: "Boş"),
                        ], height: 14)

                        HStack(spacing: 14) {
                            legend("Sistem", Theme.coral, memory.wiredBytes)
                            legend("Uygulama", Theme.indigo, memory.appMemoryBytes)
                            legend("Sıkıştırılmış", Theme.violet, memory.compressedBytes)
                            legend("Etkin değil", Theme.aqua.opacity(0.7), memory.inactiveBytes)
                            legend("Boş", Theme.mint.opacity(0.6), memory.freeBytes)
                        }
                    }
                }

                Divider().opacity(0.2)

                HStack(spacing: 22) {
                    StatBlock(value: Format.bytesCompact(memory.totalBytes), label: "Toplam RAM", size: 17)
                    StatBlock(value: Format.bytesCompact(memory.usedBytes), label: "Kullanılan", color: Theme.indigo, size: 17)
                    StatBlock(value: Format.bytesCompact(memory.availableBytes), label: "Kullanılabilir", color: Theme.mint, size: 17)
                    StatBlock(value: Format.bytesCompact(memory.cachedFilesBytes), label: "Önbelleğe alınmış dosya", size: 17)
                    StatBlock(value: Format.bytesCompact(memory.swapUsedBytes),
                              label: "Takas (disk)",
                              color: memory.swapUsedBytes > 1_000_000_000 ? Theme.amber : Theme.text, size: 17)
                }
            }
        }
    
    }

private func legend(_ title: String, _ color: Color, _ bytes: UInt64) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                Text(Format.bytesCompact(bytes)).font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
        }
    }
}

// MARK: - İşlemci

private struct CPUCard: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        GlassSection(title: "İşlemci Yükü", symbol: "cpu", accent: Theme.aqua) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 24) {
                    StatBlock(value: Format.percent(monitor.cpu.usedPercent), label: "Toplam kullanım",
                              color: Theme.aqua, size: 22)
                    StatBlock(value: Format.percent(monitor.cpu.userPercent), label: "Kullanıcı", size: 22)
                    StatBlock(value: Format.percent(monitor.cpu.systemPercent), label: "Sistem", size: 22)
                    StatBlock(value: String(format: "%.2f / %.2f / %.2f",
                                            monitor.cpu.loadAvg1, monitor.cpu.loadAvg5, monitor.cpu.loadAvg15),
                              label: "Yük ortalaması (1/5/15 dk)", size: 15)
                }

                Sparkline(values: monitor.cpuHistory,
                          gradient: Theme.gradient([Theme.aqua, Theme.mint]),
                          maximum: 100)
                    .frame(height: 90)

                HStack(spacing: 8) {
                    Pill(text: "\(monitor.hardware.performanceCores) performans çekirdeği", color: Theme.coral, symbol: "hare")
                    Pill(text: "\(monitor.hardware.efficiencyCores) verim çekirdeği", color: Theme.mint, symbol: "tortoise")
                    Pill(text: "\(monitor.hardware.gpuCores) GPU çekirdeği", color: Theme.violet, symbol: "cube.transparent")
                }
            }
        }
    
    }
}

// MARK: - Bellek tüketenler

private struct MemoryHogsCard: View {
    @Environment(SystemMonitor.self) private var monitor
    let onQuit: (ProcessInfoRow) -> Void

    var body: some View {
        let hogs = monitor.processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(10)
        // Çubuklar toplam RAM'e değil listedeki en büyüğe göre ölçeklenir;
        // aksi halde 16 GB'lık bir makinede 300 MB'lık süreç görünmez kalıyor.
        let peak = Double(hogs.first?.memoryBytes ?? 1)

        return GlassSection(title: "Belleği En Çok Kullananlar", symbol: "square.stack.3d.down.right", accent: Theme.violet,
                            trailing: AnyView(refreshButton)) {
            if hogs.isEmpty {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.frame(height: 90)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(hogs)) { process in
                        ProcessRow(
                            process: process,
                            metric: Format.bytesCompact(process.memoryBytes),
                            metricColor: Theme.violet,
                            fraction: Double(process.memoryBytes) / max(peak, 1),
                            gradient: Theme.gradient([Theme.steel, Theme.cyan])
                        ) {
                            onQuit(process)
                        }
                        if process.id != hogs.last?.id { Divider().opacity(0.12) }
                    }
                }
            }
        }
    
    }

private var refreshButton: some View {
        Button {
            monitor.refreshProcesses()
        } label: {
            Label("Yenile", systemImage: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(monitor.isLoadingProcesses)
    }
}

// MARK: - Öneriler

private struct AdvisoryCard: View {
    @Environment(SystemMonitor.self) private var monitor
    private var memory: MemorySnapshot { monitor.memory }

    var body: some View {
        GlassSection(title: "RAM Optimizasyonu", symbol: "wand.and.sparkles", accent: Theme.mint) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(advice.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(item.color)
                            .frame(width: 22, height: 22)
                            .background(item.color.opacity(0.14), in: .rect(cornerRadius: 7))
                        Text(item.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }

                Divider().opacity(0.18)

                Label {
                    Text("Aegis \"bellek temizleyici\" numarası yapmaz. macOS'un sanal bellek yöneticisi "
                         + "boş RAM'i zaten önbellek olarak kullanır; onu zorla boşaltmak sistemi yavaşlatır. "
                         + "Burada yalnızca gerçek etkisi olan işlem var: bellek tüketen uygulamayı sen kapatırsın.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle").foregroundStyle(Theme.textTertiary)
                }
            }
        }
    
    }

private var advice: [(symbol: String, color: Color, text: String)] {
        var items: [(String, Color, String)] = []

        switch memory.pressureLevel {
        case .normal:
            items.append(("checkmark.circle", Theme.mint,
                          "Bellek baskısı normal. Şu an hiçbir şey yapmana gerek yok — boş RAM boşa giden RAM değildir."))
        case .warning:
            items.append(("exclamationmark.triangle", Theme.amber,
                          "Bellek baskısı yükseliyor. Yukarıdaki listeden kullanmadığın uygulamaları kapat."))
        case .critical:
            items.append(("exclamationmark.octagon", Theme.coral,
                          "Bellek baskısı kritik. Sistem takas alanı kullanıyor; en çok bellek tüketen uygulamayı kapatman gerek."))
        }

        if memory.swapUsedBytes > 2_000_000_000 {
            items.append(("arrow.left.arrow.right.square", Theme.amber,
                          "Takas alanı \(Format.bytesCompact(memory.swapUsedBytes)). Yeniden başlatma takası sıfırlar ve sistemi belirgin hızlandırır."))
        }

        if memory.compressedBytes > memory.totalBytes / 4 {
            items.append(("archivebox", Theme.violet,
                          "Belleğin dörtte birinden fazlası sıkıştırılmış durumda — RAM talebi kapasitenin sınırında."))
        }

        let browserish = monitor.processes.filter {
            $0.memoryBytes > 1_000_000_000 && $0.canTerminate
        }
        if let heaviest = browserish.max(by: { $0.memoryBytes < $1.memoryBytes }) {
            items.append(("app.badge", Theme.indigo,
                          "\(heaviest.name) tek başına \(Format.bytesCompact(heaviest.memoryBytes)) kullanıyor. "
                          + "Sekmeleri/pencereleri azaltmak ya da yeniden başlatmak anında yer açar."))
        }

        if monitor.hardware.uptime > 7 * 86400 {
            items.append(("clock.arrow.circlepath", Theme.aqua,
                          "Mac \(Format.uptime(monitor.hardware.uptime))'dir açık. Uzun uptime bellek parçalanmasını artırır."))
        }

        return items.map { (symbol: $0.0, color: $0.1, text: $0.2) }
    }
}

// MARK: - Süreç satırı

struct ProcessRow: View {
    let process: ProcessInfoRow
    let metric: String
    let metricColor: Color
    let fraction: Double
    let gradient: LinearGradient
    let onQuit: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(pid: process.pid, bundleIdentifier: process.bundleIdentifier, isApp: process.isApp)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(process.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    if !process.isApp {
                        Text("sistem")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                MeterBar(fraction: fraction, gradient: gradient, height: 4)
                    .frame(width: 180)
            }

            Spacer(minLength: 8)

            Text(metric)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(metricColor)
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)

            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(process.canTerminate ? Theme.coral.opacity(hovering ? 1 : 0.55) : .clear)
            .disabled(!process.canTerminate)
            .help(process.canTerminate ? "Uygulamayı kapat" : "Sistem süreçleri kapatılamaz")
            .frame(width: 20)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .background(hovering ? Color.white.opacity(0.04) : .clear)
    }
}

/// Uygulama simgelerini önbelleğe alır. `NSRunningApplication(processIdentifier:)`
/// her çizimde çağrılırsa liste kaydırırken belirgin maliyet çıkarıyor.
@MainActor
enum IconCache {
    private static var storage: [String: NSImage] = [:]

    static func icon(pid: Int32, bundleIdentifier: String?) -> NSImage? {
        let key = bundleIdentifier ?? "pid:\(pid)"
        if let cached = storage[key] { return cached }
        guard let image = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        image.size = NSSize(width: 32, height: 32)
        storage[key] = image
        return image
    }
}

/// Uygulama simgesini gösterir; süreç bir GUI uygulaması değilse genel bir simge kullanır.
struct AppIcon: View {
    let pid: Int32
    let bundleIdentifier: String?
    let isApp: Bool

    var body: some View {
        Group {
            if isApp, let image = IconCache.icon(pid: pid, bundleIdentifier: bundleIdentifier) {
                Image(nsImage: image).resizable().interpolation(.medium)
            } else {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 5))
            }
        }
        .aspectRatio(contentMode: .fit)
    }
}
