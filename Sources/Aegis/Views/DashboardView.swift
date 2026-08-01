import SwiftUI

/// Genel bakış. Her kart **ayrı bir View**'dir; böylece yalnızca ilgili veri
/// değiştiğinde o kart yeniden çizilir — tüm sayfa değil. (Ölçüm: bu ayrım
/// tik başına CPU maliyetini yaklaşık üçte birine indiriyor.)
struct DashboardView: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        PageScaffold(
            title: monitor.hardware.marketingName,
            subtitle: "\(monitor.hardware.chipName) • \(monitor.hardware.osName) \(monitor.hardware.osVersion) • \(Format.uptime(monitor.hardware.uptime)) açık",
            symbol: "square.grid.2x2",
            accent: Theme.aqua,
            toolbar: AnyView(HeaderBadges())
        ) {
            ScoreCard()

            HStack(spacing: 16) {
                BatteryHeroCard()
                MemoryHeroCard()
                StorageHeroCard()
            }
            .frame(height: 218)

            InsightsCard()

            HStack(alignment: .top, spacing: 16) {
                CPUOverviewCard()
                TopEnergyCard()
            }
        }
    }
}

// MARK: - Ortak başlık

private func cardTitle(_ text: String, symbol: String, accent: Color) -> some View {
    HStack(spacing: 8) {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(accent)
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
        Spacer()
    }
}

private struct HeaderBadges: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        HStack(spacing: 8) {
            Pill(text: monitor.hardware.thermalState,
                 color: monitor.hardware.thermalState == "Normal" ? Theme.mint : Theme.amber,
                 symbol: "thermometer.medium")
            if monitor.battery.lowPowerMode {
                Pill(text: "Düşük Güç", color: Theme.amber, symbol: "leaf")
            }
        }
    }
}

// MARK: - Pil

private struct BatteryHeroCard: View {
    @Environment(SystemMonitor.self) private var monitor
    private var battery: BatterySnapshot { monitor.battery }

    var body: some View {
        GlassCard(tint: Theme.mint) {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Pil", symbol: "battery.100percent.bolt", accent: Theme.mint)

                HStack(spacing: 16) {
                    ArcGauge(
                        fraction: battery.chargePercent / 100,
                        gradient: battery.isCharging
                            ? Theme.gradient([Theme.mint, Theme.aqua])
                            : Theme.gradient(forHealth: battery.healthGrade)
                    ) {
                        VStack(spacing: 0) {
                            Text("\(Int(battery.chargePercent))")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("%")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 10) {
                        StatBlock(value: Format.percent(battery.healthPercent, decimals: 1),
                                  label: "Pil sağlığı", color: Theme.mint, size: 17)
                        StatBlock(value: "\(battery.cycleCount)",
                                  label: "Şarj döngüsü", size: 17)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Pill(text: battery.isPluggedIn ? (battery.isCharging ? "Şarj oluyor" : "Adaptör bağlı") : "Pilde",
                         color: battery.isPluggedIn ? Theme.aqua : Theme.mint,
                         symbol: battery.isPluggedIn ? "powerplug" : "battery.75percent")
                    if battery.minutesRemaining > 0 {
                        Pill(text: Format.minutes(battery.minutesRemaining), color: Theme.textSecondary, symbol: "clock")
                    }
                }
            }
        }
    }
}

// MARK: - Bellek

private struct MemoryHeroCard: View {
    @Environment(SystemMonitor.self) private var monitor
    private var memory: MemorySnapshot { monitor.memory }

    var body: some View {
        GlassCard(tint: Theme.indigo) {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Bellek", symbol: "memorychip", accent: Theme.indigo)

                HStack(spacing: 16) {
                    RingGauge(
                        fraction: memory.pressurePercent / 100,
                        gradient: Theme.gradient([Theme.color(forPressure: memory.pressureLevel),
                                                  Theme.color(forPressure: memory.pressureLevel).opacity(0.55)])
                    ) {
                        VStack(spacing: 0) {
                            Text("\(Int(memory.pressurePercent))")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                            Text("baskı")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 10) {
                        StatBlock(value: Format.bytesCompact(memory.usedBytes),
                                  label: "Kullanılan / \(Format.bytesCompact(memory.totalBytes))",
                                  color: Theme.indigo, size: 17)
                        StatBlock(value: Format.bytesCompact(memory.swapUsedBytes),
                                  label: "Takas alanı", size: 17)
                    }
                }

                Spacer(minLength: 0)

                Sparkline(values: monitor.memoryHistory,
                          gradient: Theme.gradient([Theme.indigo, Theme.violet]),
                          maximum: 100)
                    .frame(height: 26)
            }
        }
    }
}

// MARK: - Depolama

private struct StorageHeroCard: View {
    @Environment(SystemMonitor.self) private var monitor

    private var volume: VolumeInfo? {
        monitor.volumes.first(where: { $0.isInternal }) ?? monitor.volumes.first
    }

    var body: some View {
        GlassCard(tint: Theme.violet) {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Depolama", symbol: "internaldrive", accent: Theme.violet)

                if let volume {
                    HStack(spacing: 16) {
                        RingGauge(
                            fraction: volume.usedFraction,
                            gradient: Theme.gradient([Theme.usageColor(volume.usedFraction),
                                                      Theme.usageColor(volume.usedFraction).opacity(0.5)])
                        ) {
                            VStack(spacing: 0) {
                                Text("\(Int(volume.usedFraction * 100))")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                Text("dolu")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(width: 96, height: 96)

                        VStack(alignment: .leading, spacing: 10) {
                            StatBlock(value: Format.bytesCompact(volume.availableForImportantBytes),
                                      label: "Kullanılabilir", color: Theme.violet, size: 17)
                            StatBlock(value: Format.bytesCompact(volume.totalBytes),
                                      label: "Toplam kapasite", size: 17)
                        }
                    }
                    Spacer(minLength: 0)
                    Pill(text: volume.name, color: Theme.violet, symbol: "externaldrive")
                } else {
                    Spacer()
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - İçgörüler

private struct InsightsCard: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        GlassSection(title: "Sistem Değerlendirmesi", symbol: "sparkle.magnifyingglass", accent: Theme.amber) {
            VStack(spacing: 10) {
                ForEach(monitor.insights) { insight in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: insight.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(insight.severity.color)
                            .frame(width: 26, height: 26)
                            .background(insight.severity.color.opacity(0.15), in: .rect(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(insight.detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

// MARK: - İşlemci

private struct CPUOverviewCard: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        GlassSection(title: "İşlemci", symbol: "cpu", accent: Theme.aqua) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(Format.percent(monitor.cpu.usedPercent))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("kullanım")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Pill(text: "Yük \(String(format: "%.2f", monitor.cpu.loadAvg1))", color: Theme.aqua)
                }

                Sparkline(values: monitor.cpuHistory,
                          gradient: Theme.gradient([Theme.aqua, Theme.mint]),
                          maximum: 100)
                    .frame(height: 52)

                HStack(spacing: 18) {
                    StatBlock(value: Format.percent(monitor.cpu.userPercent), label: "Kullanıcı", size: 14)
                    StatBlock(value: Format.percent(monitor.cpu.systemPercent), label: "Sistem", size: 14)
                    StatBlock(value: Format.percent(monitor.cpu.idlePercent), label: "Boşta", size: 14)
                }
            }
        }
    }
}

// MARK: - Enerji özeti

private struct TopEnergyCard: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        GlassSection(title: "En Çok Enerji Tüketenler", symbol: "bolt.fill", accent: Theme.amber) {
            let top = monitor.processes.sorted { $0.energyImpact > $1.energyImpact }.prefix(5)
            if top.isEmpty {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .frame(height: 120)
            } else {
                VStack(spacing: 9) {
                    ForEach(Array(top)) { process in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Theme.color(forEnergy: process.energyBand))
                                .frame(width: 6, height: 6)
                            Text(process.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(String(format: "%.0f", process.energyImpact))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.color(forEnergy: process.energyBand))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}
