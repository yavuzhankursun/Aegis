import SwiftUI

struct HardwareView: View {
    @Environment(SystemMonitor.self) private var monitor
    @State private var revealSerial = false

    private var hardware: HardwareInfo { monitor.hardware }

    var body: some View {
        PageScaffold(
            title: "Donanım",
            subtitle: "Bu Mac'in tam künyesi — sysctl, IORegistry ve system_profiler kaynaklı",
            symbol: "cpu",
            accent: Theme.titanium,
            toolbar: AnyView(Pill(text: hardware.architecture, color: Theme.titanium, symbol: "cpu"))
        ) {
            heroCard
            HStack(alignment: .top, spacing: 16) {
                chipCard
                systemCard
            }
            displaysCard
        }
    }

    private var heroCard: some View {
        GlassCard(tint: Theme.indigo) {
            HStack(spacing: 22) {
                Image(systemName: modelSymbol)
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(Theme.gradient([Theme.aqua, Theme.indigo]))
                    .frame(width: 84)

                VStack(alignment: .leading, spacing: 6) {
                    Text(hardware.marketingName)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("\(hardware.chipName) • \(hardware.memoryType) bellek • \(hardware.modelIdentifier)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)

                    HStack(spacing: 7) {
                        Pill(text: "\(hardware.osName) \(hardware.osVersion)", color: Theme.mint, symbol: "apple.logo")
                        Pill(text: "Build \(hardware.osBuild)", color: Theme.textSecondary)
                        Pill(text: Format.uptime(hardware.uptime) + " açık", color: Theme.aqua, symbol: "clock")
                        if let sip = hardware.sipEnabled {
                            Pill(text: sip ? "SIP açık" : "SIP KAPALI",
                                 color: sip ? Theme.mint : Theme.coral,
                                 symbol: sip ? "lock.shield" : "lock.open")
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private var modelSymbol: String {
        let name = hardware.marketingName.lowercased()
        if name.contains("macbook") { return "laptopcomputer" }
        if name.contains("imac") { return "desktopcomputer" }
        if name.contains("mac mini") { return "macmini" }
        if name.contains("mac studio") { return "macstudio" }
        if name.contains("mac pro") { return "macpro.gen3" }
        return "desktopcomputer"
    }

    private var chipCard: some View {
        GlassSection(title: "İşlemci ve Grafik", symbol: "cpu", accent: Theme.aqua) {
            VStack(spacing: 14) {
                HStack(spacing: 20) {
                    StatBlock(value: "\(hardware.totalCores)", label: "Toplam çekirdek", color: Theme.aqua, size: 22)
                    StatBlock(value: "\(hardware.performanceCores)", label: "Performans", color: Theme.coral, size: 22)
                    StatBlock(value: "\(hardware.efficiencyCores)", label: "Verimlilik", color: Theme.mint, size: 22)
                    StatBlock(value: hardware.gpuCores > 0 ? "\(hardware.gpuCores)" : "—",
                              label: "GPU çekirdeği", color: Theme.violet, size: 22)
                }

                Divider().opacity(0.18)

                VStack(spacing: 9) {
                    KeyValueRow(key: "Yonga", value: hardware.chipName)
                    KeyValueRow(key: "Mimari", value: hardware.architecture)
                    KeyValueRow(key: "Model tanımlayıcı", value: hardware.modelIdentifier, mono: true)
                    KeyValueRow(key: "Bellek", value: hardware.memoryType)
                    KeyValueRow(key: "Termal durum", value: hardware.thermalState)
                }
            }
        }
    }

    private var systemCard: some View {
        GlassSection(title: "Sistem", symbol: "gearshape", accent: Theme.mint) {
            VStack(spacing: 9) {
                KeyValueRow(key: "İşletim sistemi", value: "\(hardware.osName) \(hardware.osVersion)")
                KeyValueRow(key: "Derleme", value: hardware.osBuild, mono: true)
                KeyValueRow(key: "Çekirdek", value: hardware.kernel, mono: true)
                KeyValueRow(key: "Çalışma süresi", value: Format.uptime(hardware.uptime))
                KeyValueRow(key: "SIP", value: hardware.sipEnabled.map { $0 ? "Etkin" : "Devre dışı" } ?? "Bilinmiyor")

                HStack(alignment: .firstTextBaseline) {
                    Text("Seri numarası")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 12)
                    if revealSerial {
                        Text(hardware.serialNumber)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text(String(repeating: "•", count: max(hardware.serialNumber.count, 8)))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Button {
                        revealSerial.toggle()
                    } label: {
                        Image(systemName: revealSerial ? "eye.slash" : "eye")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var displaysCard: some View {
        GlassSection(title: "Ekranlar", symbol: "display", accent: Theme.violet) {
            if hardware.displays.isEmpty {
                Text("Ekran bilgisi okunamadı.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(hardware.displays) { display in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 7) {
                                Image(systemName: display.isMain ? "display" : "display.2")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.violet)
                                Text(display.name)
                                    .font(.system(size: 13, weight: .semibold))
                                if display.isMain {
                                    Pill(text: "Ana", color: Theme.violet)
                                }
                            }
                            KeyValueRow(key: "Çözünürlük", value: "\(display.pixelWidth) × \(display.pixelHeight)")
                            KeyValueRow(key: "Yenileme", value: String(format: "%.0f Hz", display.refreshHz))
                            KeyValueRow(key: "Ölçek", value: String(format: "%.1fx", display.scale))
                        }
                        .frame(maxWidth: 280, alignment: .leading)
                    }
                    Spacer()
                }
            }
        }
    }
}
