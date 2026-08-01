import SwiftUI

/// Pil sekmesi. Gövde yalnızca `battery.isPresent` bilgisini okur;
/// tüm canlı ölçümler alt kartların kendi gözlem kapsamındadır.
struct BatteryView: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        PageScaffold(
            title: "Pil",
            subtitle: monitor.battery.isPresent
                ? "Sağlık, döngü ve anlık güç akışı — doğrudan AppleSmartBattery kaydından"
                : "Bu Mac'te dahili pil bulunamadı",
            symbol: "battery.100percent.bolt",
            accent: Theme.teal,
            toolbar: AnyView(BatteryConditionBadge())
        ) {
            if monitor.battery.isPresent {
                BatteryChargeCard()
                BatteryForecastCard()
                BatteryCycleCard()
                BatteryTelemetryCard()
                BatteryIdentityCard()
            } else {
                GlassCard {
                    Label("Masaüstü Mac veya pil okunamıyor.", systemImage: "bolt.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

// MARK: - Alt kartlar
//
// Her kart ayrı bir `View`: pil 5 saniyede bir, gauge ömür kaydı ise daha
// seyrek güncellenir. Tek gövdede toplansalardı bir sıcaklık değişimi
// hücre dengesi grafiğini de baştan çizdirirdi.

private struct BatteryChargeCard: View {
    @Environment(SystemMonitor.self) private var monitor
    private var battery: BatterySnapshot { monitor.battery }

    var body: some View {
        HStack(spacing: 16) {
            GlassCard(tint: Theme.mint) {
                VStack(spacing: 14) {
                    ArcGauge(
                        fraction: battery.chargePercent / 100,
                        gradient: Theme.gradient([Theme.mint, Theme.aqua]),
                        lineWidth: 16
                    ) {
                        VStack(spacing: 2) {
                            Text("\(Int(battery.chargePercent))%")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text(battery.isCharging ? "şarj oluyor" : (battery.isPluggedIn ? "adaptörde" : "deşarj"))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 150, height: 150)

                    Text(battery.minutesRemaining > 0
                         ? "\(Format.minutes(battery.minutesRemaining)) kaldı"
                         : "Kalan süre hesaplanıyor")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: 268)

            VStack(spacing: 16) {
                healthCard
                powerFlowCard
            }
        }
    
    }

private var healthCard: some View {
        GlassSection(title: "Pil Sağlığı", symbol: "heart.text.square", accent: gradeColor) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(Format.percent(battery.healthPercent, decimals: 1))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(gradeColor)
                    Text("tasarım kapasitesinin")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }

                MeterBar(fraction: battery.healthPercent / 100,
                         gradient: Theme.gradient(forHealth: battery.healthGrade),
                         height: 10)

                HStack(spacing: 20) {
                    StatBlock(value: "\(battery.currentMaxCapacity) mAh", label: "Şu anki tam kapasite", size: 15)
                    StatBlock(value: "\(battery.designCapacity) mAh", label: "Tasarım kapasitesi", size: 15)
                    StatBlock(value: "\(max(0, battery.designCapacity - battery.currentMaxCapacity)) mAh",
                              label: "Kaybedilen kapasite", color: Theme.amber, size: 15)
                }
            }
        }
    }

private var powerFlowCard: some View {
        GlassSection(title: "Anlık Güç Akışı", symbol: "bolt.horizontal", accent: Theme.amber) {
            HStack(spacing: 20) {
                StatBlock(value: String(format: "%.1f W", battery.wattage),
                          label: battery.isCharging ? "Şarj gücü" : "Çekilen güç",
                          symbol: "bolt.fill", color: Theme.amber, size: 19)
                StatBlock(value: String(format: "%.2f V", battery.voltage),
                          label: "Gerilim", symbol: "waveform.path", size: 19)
                StatBlock(value: String(format: "%.2f A", abs(battery.amperage)),
                          label: "Akım", symbol: "arrow.left.arrow.right", size: 19)
                StatBlock(value: Format.temperature(battery.temperatureC),
                          label: "Sıcaklık",
                          symbol: "thermometer.medium",
                          color: battery.temperatureC > 40 ? Theme.orange : Theme.text,
                          size: 19)
            }
        }
    }

private var gradeColor: Color {
        switch battery.healthGrade {
        case .excellent, .good: return Theme.mint
        case .fair: return Theme.amber
        case .critical: return Theme.coral
        }
    }
}

private struct BatteryForecastCard: View {
    @Environment(SystemMonitor.self) private var monitor
    private var battery: BatterySnapshot { monitor.battery }
    private var forecast: BatteryForecast { monitor.batteryForecast }

    var body: some View {
        GlassSection(title: "Aşınma Tahmini", symbol: "chart.line.downtrend.xyaxis", accent: Theme.amber) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 24) {
                    StatBlock(value: forecast.wearIsNegligible
                                ? "ölçülemedi"
                                : Format.percent(forecast.wearPerCycle, decimals: 4),
                              label: "Döngü başına kayıp", symbol: "arrow.down.right",
                              color: Theme.amber, size: 19)
                    StatBlock(value: forecast.cyclesTo80Percent >= 0 ? "\(forecast.cyclesTo80Percent)" : "—",
                              label: "%80'e kalan döngü", symbol: "flag.checkered", size: 19)
                    StatBlock(value: forecast.cyclesPerDay > 0 ? String(format: "%.2f", forecast.cyclesPerDay) : "—",
                              label: "Günlük döngü temposu", symbol: "speedometer", size: 19)
                    StatBlock(value: forecast.horizonExceeded
                                ? "10+ yıl"
                                : forecast.estimatedDate.map { Format.date($0) } ?? "—",
                              label: "%80 eşiği tahmini", symbol: "calendar",
                              color: Theme.cyan, size: 19)
                }

                // Şimdi → %80 eşiği yolu
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                    GeometryReader { geo in
                        Capsule()
                            .fill(Theme.gradient([Theme.teal, Theme.amber]))
                            .frame(width: geo.size.width * min(1, max(0.02, (100 - battery.healthPercent) / 20)),
                                   height: 8)
                    }
                    .frame(height: 8)
                }
                .frame(height: 8)

                HStack {
                    Text("%100")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text("şu an " + Format.percent(battery.healthPercent, decimals: 1))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("%80 · değişim eşiği")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                }

                Text(forecast.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Tahmin, mevcut aşınma hızının sabit kalacağı varsayımına dayanır. "
                     + "Günlük tempo, gauge yongasının bildirdiği toplam çalışma süresinden türetilir.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    
    }
}

private struct BatteryCycleCard: View {
    @Environment(SystemMonitor.self) private var monitor
    private var battery: BatterySnapshot { monitor.battery }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            GlassSection(title: "Şarj Döngüsü", symbol: "arrow.triangle.2.circlepath", accent: Theme.aqua) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(battery.cycleCount)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("/ 1000 döngü")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }

                    MeterBar(fraction: battery.cycleLifePercent,
                             gradient: Theme.gradient([Theme.aqua, Theme.indigo]),
                             height: 10)

                    Text(cycleAdvice)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GlassSection(title: "Şarj Geçmişi (bu oturum)", symbol: "chart.xyaxis.line", accent: Theme.mint) {
                VStack(alignment: .leading, spacing: 8) {
                    Sparkline(values: monitor.batteryHistory,
                              gradient: Theme.gradient([Theme.mint, Theme.aqua]),
                              maximum: 100)
                        .frame(height: 86)
                    Text("Uygulama açık olduğu sürece örneklenir. Kapanınca sıfırlanır.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    
    }

private var cycleAdvice: String {
        switch battery.cycleCount {
        case ..<200: return "Pil neredeyse yeni. %80'de tutmak (Optimize Edilmiş Şarj) ömrü belirgin şekilde uzatır."
        case ..<600: return "Normal aralıkta. Sürekli %100'de tutmaktan ve 35°C üstü sıcaklıklardan kaçın."
        case ..<900: return "Ömrünün ikinci yarısında. Kapasite düşüşünü izlemeye devam et."
        default: return "Tasarım ömrünü doldurmak üzere. Kapasite %80'in altına inerse değişim zamanı."
        }
    }
}

private struct BatteryTelemetryCard: View {
    @Environment(SystemMonitor.self) private var monitor
    private var lifetime: BatteryLifetime { monitor.batteryLifetime }

    var body: some View {
        GlassSection(title: "Gauge Ömür Kaydı", symbol: "waveform.path.ecg.rectangle", accent: Theme.steel,
                     trailing: AnyView(Pill(text: lifetime.isAvailable ? "canlı" : "okunamadı",
                                            color: lifetime.isAvailable ? Theme.teal : Theme.crimson,
                                            symbol: "dot.radiowaves.left.and.right"))) {
            if !lifetime.isAvailable {
                Text("Pil gauge kaydı okunamadı.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bu değerler pilin içindeki ölçüm yongasının ömür boyu tuttuğu kayıttan gelir — "
                         + "Sistem Bilgisi'nde de Activity Monitor'da da görünmez.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 22) {
                        StatBlock(value: Format.hours(lifetime.totalOperatingHours),
                                  label: "Toplam çalışma", symbol: "clock.arrow.circlepath", size: 17)
                        StatBlock(value: "\(lifetime.minimumTemperatureC)–\(lifetime.maximumTemperatureC)°C",
                                  label: "Görülen sıcaklık aralığı", symbol: "thermometer.variable",
                                  color: lifetime.maximumTemperatureC >= 45 ? Theme.orange : Theme.text, size: 17)
                        StatBlock(value: String(format: "%.1f°C", lifetime.averageTemperatureC),
                                  label: "Ömür boyu ortalama", symbol: "thermometer.medium", size: 17)
                        StatBlock(value: "\(lifetime.maximumChargeCurrentmA) mA",
                                  label: "En yüksek şarj akımı", symbol: "bolt.badge.clock", size: 17)
                    }

                    Divider().opacity(0.15)

                    HStack(alignment: .top, spacing: 28) {
                        cellBalance
                        VStack(spacing: 8) {
                            KeyValueRow(key: "Paket gerilim aralığı",
                                        value: "\(lifetime.minimumPackVoltagemV) – \(lifetime.maximumPackVoltagemV) mV")
                            KeyValueRow(key: "En yüksek deşarj akımı",
                                        value: "\(abs(lifetime.maximumDischargeCurrentmA)) mA")
                            KeyValueRow(key: "Günlük şarj penceresi",
                                        value: "%\(lifetime.dailyMinSoc) – %\(lifetime.dailyMaxSoc)")
                            KeyValueRow(key: "Kimya kodu / flash yazma",
                                        value: "\(lifetime.chemistryID) · \(lifetime.flashWriteCount)", mono: true)
                        }
                    }

                    chargeHabitAdvice
                }
            }
        }
    
    }

private var cellBalance: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("HÜCRE DENGESİ")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(Theme.textTertiary)
                Pill(text: lifetime.balanceVerdict.text,
                     color: lifetime.balanceVerdict.healthy ? Theme.teal : Theme.crimson)
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(lifetime.cellVoltagesmV.enumerated()), id: \.offset) { index, millivolts in
                    VStack(spacing: 5) {
                        Text("\(millivolts)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .monospacedDigit()
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.gradient([Theme.cyan, Theme.steel]))
                            .frame(width: 26, height: barHeight(for: millivolts))
                        Text("H\(index + 1)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                if lifetime.cellVoltagesmV.isEmpty {
                    Text("Hücre verisi yok").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Δ \(lifetime.cellImbalancemV) mV")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(lifetime.balanceVerdict.healthy ? Theme.teal : Theme.crimson)
                        Text("hücreler arası fark")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.leading, 6)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(width: 300, alignment: .leading)
    }

private func barHeight(for millivolts: Int) -> CGFloat {
        let normalized = (Double(millivolts) - 3600) / 600
        return 20 + CGFloat(min(1, max(0, normalized))) * 32
    }

private var chargeHabitAdvice: some View {
        let hot = lifetime.maximumTemperatureC >= 45
        let alwaysFull = lifetime.dailyMaxSoc >= 95 && lifetime.dailyMinSoc >= 70
        let deepCycles = lifetime.dailyMinSoc > 0 && lifetime.dailyMinSoc <= 15

        return VStack(alignment: .leading, spacing: 8) {
            if hot {
                habit("thermometer.sun.fill", Theme.orange,
                      "Pil ömrü boyunca \(lifetime.maximumTemperatureC)°C gördü. 45°C üstü, kalıcı kapasite kaybının bir numaralı sebebidir — şarjdayken ağır iş yaparken havalandırmaya dikkat.")
            }
            if alwaysFull {
                habit("battery.100percent", Theme.amber,
                      "Pil çoğunlukla %\(lifetime.dailyMinSoc)–%\(lifetime.dailyMaxSoc) bandında tutuluyor. Sürekli dolu kalmak hücre gerilimini yüksek tutar; Optimize Edilmiş Şarj'ı açık tut.")
            }
            if deepCycles {
                habit("battery.25percent", Theme.orange,
                      "Pil düzenli olarak %\(lifetime.dailyMinSoc)'e kadar iniyor. Derin deşarj döngü ömrünü kısaltır; %20 altına düşmeden şarja takmak daha iyi.")
            }
            if !hot && !alwaysFull && !deepCycles {
                habit("checkmark.seal.fill", Theme.teal,
                      "Şarj ve sıcaklık alışkanlıkların pil için ideal aralıkta. Böyle devam.")
            }
        }
    }

private func habit(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.13), in: .rect(cornerRadius: 7))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct BatteryIdentityCard: View {
    @Environment(SystemMonitor.self) private var monitor
    private var battery: BatterySnapshot { monitor.battery }

    var body: some View {
        GlassSection(title: "Pil Künyesi", symbol: "info.circle", accent: Theme.violet) {
            HStack(alignment: .top, spacing: 32) {
                VStack(spacing: 9) {
                    KeyValueRow(key: "Seri numarası", value: battery.serial, mono: true)
                    KeyValueRow(key: "Durum", value: battery.condition)
                    KeyValueRow(key: "Kalıcı arıza", value: battery.permanentFailure ? "VAR" : "Yok")
                }
                VStack(spacing: 9) {
                    KeyValueRow(key: "Ham tam kapasite", value: "\(battery.rawMaxCapacity) mAh")
                    KeyValueRow(key: "Düşük güç modu", value: battery.lowPowerMode ? "Açık" : "Kapalı")
                    KeyValueRow(key: "Adaptör", value: battery.isPluggedIn ? "Bağlı" : "Bağlı değil")
                }
            }
        }
    
    }
}

private struct BatteryConditionBadge: View {
    @Environment(SystemMonitor.self) private var monitor
    private var battery: BatterySnapshot { monitor.battery }

    var body: some View {
        HStack(spacing: 8) {
            Pill(text: battery.condition,
                 color: battery.healthGrade == .critical ? Theme.coral : Theme.mint,
                 symbol: "checkmark.seal")
            Pill(text: battery.healthGrade.rawValue,
                 color: gradeColor,
                 symbol: "heart.text.square")
        }
    
    }

private var gradeColor: Color {
        switch battery.healthGrade {
        case .excellent, .good: return Theme.mint
        case .fair: return Theme.amber
        case .critical: return Theme.coral
        }
    }
}
