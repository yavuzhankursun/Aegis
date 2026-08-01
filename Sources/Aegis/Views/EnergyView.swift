import SwiftUI

/// Enerji sekmesi. Süreç listesi 4 saniyede bir tazelenir; özet kartları ise
/// pil verisiyle güncellenir. İkisi ayrı `View` olduğundan biri diğerini
/// yeniden çizdirmez.
struct EnergyView: View {
    @Environment(SystemMonitor.self) private var monitor
    @State private var sortKey: SortKey = .energy
    @State private var quitCandidate: ProcessInfoRow?
    @State private var onlyApps = false

    enum SortKey: String, CaseIterable, Identifiable, Sendable {
        case energy = "Enerji"
        case cpu = "İşlemci"
        case memory = "Bellek"
        var id: String { rawValue }
    }

    

    
    

    var body: some View {
        PageScaffold(
            title: "Enerji",
            subtitle: "macOS'un kendi Energy Impact ölçümüyle güç tüketen süreçler",
            symbol: "bolt.horizontal",
            accent: Theme.amber,
            toolbar: AnyView(toolbar)
        ) {
            EnergySummaryRow()
            EnergyProcessList(sortKey: sortKey, onlyApps: onlyApps) { quitCandidate = $0 }
            EnergyExplanationCard()
        }
        .alert("Uygulamayı kapat", isPresented: .init(
            get: { quitCandidate != nil },
            set: { if !$0 { quitCandidate = nil } }
        ), presenting: quitCandidate) { process in
            Button("Vazgeç", role: .cancel) { quitCandidate = nil }
            Button("Kapat", role: .destructive) {
                _ = ProcessTerminator.requestQuit(pid: process.pid)
                quitCandidate = nil
                Task { try? await Task.sleep(for: .seconds(2)); monitor.refreshProcesses() }
            }
        } message: { process in
            Text("\(process.name) kapatma isteği alacak. Kaydedilmemiş veri varsa uygulama sana soracak.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Toggle("Sadece uygulamalar", isOn: $onlyApps)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11))

            Picker("", selection: $sortKey) {
                ForEach(SortKey.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 210)
            .labelsHidden()
        }
    }

    // MARK: - Özet

    

    // MARK: - Liste

    

    

    

    

    
}


// MARK: - Özet kartları (yalnızca pil + süreç sayısı okur)

private struct EnergySummaryRow: View {
    @Environment(SystemMonitor.self) private var monitor

    private var totalEnergy: Double { monitor.processes.reduce(0) { $0 + $1.energyImpact } }

    var body: some View {
        HStack(spacing: 16) {
            GlassCard(tint: Theme.amber) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Toplam Enerji Etkisi")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(String(format: "%.0f", totalEnergy))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.amber)
                    Text(monitor.battery.isPluggedIn
                         ? "Adaptöre bağlısın — bu değer pili etkilemiyor."
                         : "Pil boşalma hızını doğrudan belirler.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 220)

            GlassCard {
                HStack(spacing: 26) {
                    StatBlock(value: String(format: "%.1f W", monitor.battery.wattage),
                              label: monitor.battery.isCharging ? "Şarj gücü" : "Anlık güç çekişi",
                              symbol: "bolt.fill", color: Theme.amber, size: 21)
                    StatBlock(value: monitor.battery.minutesRemaining > 0
                                ? Format.minutes(monitor.battery.minutesRemaining) : "—",
                              label: "Tahmini kalan süre", symbol: "clock", size: 21)
                    StatBlock(value: "\(monitor.processes.count)",
                              label: "İzlenen süreç", symbol: "list.bullet", size: 21)
                    StatBlock(value: monitor.battery.lowPowerMode ? "Açık" : "Kapalı",
                              label: "Düşük güç modu", symbol: "leaf",
                              color: monitor.battery.lowPowerMode ? Theme.mint : Theme.text, size: 21)
                }
            }
        }
    
    }
}

// MARK: - Süreç listesi

private struct EnergyProcessList: View {
    @Environment(SystemMonitor.self) private var monitor
    let sortKey: EnergyView.SortKey
    let onlyApps: Bool
    let onQuit: (ProcessInfoRow) -> Void

    private var rows: [ProcessInfoRow] {
        let base = onlyApps ? monitor.processes.filter(\.isApp) : monitor.processes
        switch sortKey {
        case .energy: return base.sorted { $0.energyImpact > $1.energyImpact }
        case .cpu: return base.sorted { $0.cpuPercent > $1.cpuPercent }
        case .memory: return base.sorted { $0.memoryBytes > $1.memoryBytes }
        }
    }

    private var maxEnergy: Double { max(monitor.processes.map(\.energyImpact).max() ?? 1, 1) }

    var body: some View {
        GlassSection(title: "Süreçler", symbol: "list.bullet.rectangle", accent: Theme.amber,
                     trailing: AnyView(refreshButton)) {
            if monitor.processes.isEmpty {
                HStack { Spacer(); ProgressView("Süreçler örnekleniyor…").controlSize(.small); Spacer() }
                    .frame(height: 120)
            } else {
                VStack(spacing: 0) {
                    header
                    Divider().opacity(0.18)
                    ForEach(rows.prefix(25)) { process in
                        EnergyRow(process: process, maxEnergy: maxEnergy) {
                            onQuit(process)
                        }
                        Divider().opacity(0.10)
                    }
                }
            }
        }
    
    }

private var header: some View {
        HStack(spacing: 12) {
            Text("Uygulama / Süreç")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Enerji").frame(width: 108, alignment: .trailing)
            Text("CPU").frame(width: 62, alignment: .trailing)
            Text("Bellek").frame(width: 78, alignment: .trailing)
            Spacer().frame(width: 24)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .padding(.bottom, 6)
    }

private var refreshButton: some View {
        Button {
            monitor.refreshProcesses()
        } label: {
            Label(monitor.isLoadingProcesses ? "Örnekleniyor…" : "Yenile", systemImage: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(monitor.isLoadingProcesses)
    }
}

// MARK: - Açıklama (durağan içerik, hiç yeniden çizilmez)

private struct EnergyExplanationCard: View {
    var body: some View {
        GlassSection(title: "Bu Sayılar Ne Anlama Geliyor?", symbol: "questionmark.circle", accent: Theme.aqua) {
            VStack(alignment: .leading, spacing: 10) {
                bullet("Enerji Etkisi", "macOS'un birleşik ölçütü: CPU zamanı, uyandırma sayısı, disk ve GPU aktivitesini birlikte değerlendirir. Activity Monitor'daki 'Energy Impact' ile aynı kaynaktan gelir.")
                bullet("20 üzeri", "Süreç pil ömrünü fark edilir şekilde kısaltıyor.")
                bullet("50 üzeri", "Ciddi tüketim. Genelde arka planda takılı kalmış bir işlem, video kod çözme veya sonsuz döngüdür.")
                bullet("Kapatılamayan satırlar", "Sistem daemon'ları. Aegis bunlara sinyal göndermez — kararlılığı bozmamak için tasarım gereği engellidir.")
            }
        }
    
    }

private func bullet(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Theme.aqua).frame(width: 5, height: 5).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct EnergyRow: View {
    let process: ProcessInfoRow
    let maxEnergy: Double
    let onQuit: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(pid: process.pid, bundleIdentifier: process.bundleIdentifier, isApp: process.isApp)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(verbatim: "PID " + String(process.pid))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 7) {
                MeterBar(fraction: process.energyImpact / maxEnergy,
                         gradient: Theme.gradient([Theme.color(forEnergy: process.energyBand),
                                                   Theme.color(forEnergy: process.energyBand).opacity(0.5)]),
                         height: 5)
                    .frame(width: 58)
                Text(String(format: "%.0f", process.energyImpact))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.color(forEnergy: process.energyBand))
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
            .frame(width: 108, alignment: .trailing)

            Text(String(format: "%.1f%%", process.cpuPercent))
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(width: 62, alignment: .trailing)

            Text(Format.bytesCompact(process.memoryBytes))
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(width: 78, alignment: .trailing)

            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(process.canTerminate ? Theme.coral.opacity(hovering ? 1 : 0.5) : .clear)
            .disabled(!process.canTerminate)
            .frame(width: 24)
        }
        .padding(.vertical, 7)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .background(hovering ? Color.white.opacity(0.04) : .clear)
    }
}
