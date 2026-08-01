import SwiftUI

struct RootView: View {
    @Environment(SystemMonitor.self) private var monitor
    @State private var cleanup = CleanupStore()

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 218)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 1)

            ZStack {
                content
                    // Apple'ın kendi geçişi: bulanıklaşarak yer değiştirme.
                    // Sadece sekme değişiminde bir kez çalışır, sürekli maliyeti yok.
                    .transition(.blurReplace.combined(with: .offset(y: 10)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.smooth(duration: 0.32, extraBounce: 0.05), value: monitor.activeSection)
        }
        .environment(cleanup)
        // Varsayılan metin rengini tek noktadan sabitler: koyu kokpit yüzeyinde
        // hiyerarşik sistem renklerine güvenmiyoruz.
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .tint(Theme.cyan)
    }

    @ViewBuilder
    private var content: some View {
        switch monitor.activeSection {
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

// MARK: - Kenar çubuğu

private struct Sidebar: View {
    @Environment(SystemMonitor.self) private var monitor
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 30)
                .padding(.bottom, 24)

            VStack(spacing: 3) {
                ForEach(SystemMonitor.Section.allCases) { section in
                    SidebarItem(
                        section: section,
                        isSelected: monitor.activeSection == section,
                        badge: badge(for: section),
                        namespace: selectionNamespace
                    ) {
                        withAnimation(.smooth(duration: 0.32, extraBounce: 0.08)) {
                            monitor.activeSection = section
                        }
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 12)

            footer
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.void.opacity(0.55))
        .background(.ultraThinMaterial.opacity(0.5))
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.gradient([Theme.steel, Theme.cyan]))
                    .frame(width: 32, height: 32)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.void)
            }
            .shadow(color: Theme.cyan.opacity(0.35), radius: 9, y: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text("AEGIS")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .kerning(2.2)
                    .foregroundStyle(Theme.text)
                Text("MAC CONTROL")
                    .font(.system(size: 8, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                LiveIndicator(active: monitor.isSampling)
                Text(monitor.isSampling ? "CANLI" : "DURAKLADI")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(monitor.isSampling ? Theme.teal : Theme.textTertiary)
                Spacer()
            }
            Text("Salt okunur telemetri · silme yalnızca onayınla")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func badge(for section: SystemMonitor.Section) -> String? {
        switch section {
        case .dashboard:
            return monitor.score.total > 0 ? "\(Int(monitor.score.total))" : nil
        case .battery:
            return monitor.battery.isPresent ? "\(Int(monitor.battery.chargePercent))%" : nil
        case .performance:
            return monitor.cpu.usedPercent > 0 ? "\(Int(monitor.cpu.usedPercent))%" : nil
        case .storage:
            guard let main = monitor.volumes.first(where: { $0.isInternal }) else { return nil }
            return "\(Int(main.usedFraction * 100))%"
        default:
            return nil
        }
    }
}

/// Canlı izleme göstergesi — kasten **animasyonsuz**.
///
/// **Ölçüm notu (iki tur):**
/// 1. Önce `.symbolEffect(.variableColor.iterative)` vardı. Sürekli tekrarlayan
///    sembol animasyonu tek başına **%16 CPU** yiyordu; hiçbir veri değişmese bile.
/// 2. Yerine örnekleme başına bir kez çalışan 0,3 sn'lik bir nabız kondu.
///    O bile CPU'yu %1,7'den **%6,1'e** çıkardı.
///
/// Sebep: bu gösterge `.ultraThinMaterial` bir yüzeyin üstünde duruyor.
/// Materyal/cam üzerinde animasyon yapmak, animasyon süresince arka planın
/// ekran tazeleme hızında (120 Hz) yeniden bulanıklaştırılmasını zorluyor —
/// hareket eden nokta 6 piksel olsa bile.
///
/// Kural: cam yüzeyler üzerinde **sürekli veya periyodik** animasyon yok.
/// Animasyon yalnızca kullanıcı bir şey yaptığında (sekme değişimi, hover,
/// bir değerin gerçekten değişmesi) çalışır — boştayken maliyeti sıfırdır.
private struct LiveIndicator: View {
    let active: Bool

    var body: some View {
        Circle()
            .fill(active ? Theme.teal : Theme.textTertiary)
            .frame(width: 6, height: 6)
            .overlay(
                Circle().stroke(active ? Theme.teal.opacity(0.35) : .clear, lineWidth: 3)
            )
    }
}

private struct SidebarItem: View {
    let section: SystemMonitor.Section
    let isSelected: Bool
    let badge: String?
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? section.accent : Theme.textSecondary)
                    .frame(width: 18)
                    .symbolEffect(.bounce, value: isSelected)

                Text(section.rawValue)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)

                Spacer(minLength: 4)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? section.accent : Theme.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    // Seçim vurgusu tek bir katman olarak kayar (matchedGeometryEffect):
                    // Apple'ın segmented control hissi, sıfır sürekli maliyet.
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(section.accent.opacity(0.14))
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(section.accent.opacity(0.32), lineWidth: 0.7)
                        HStack {
                            Capsule()
                                .fill(section.accent)
                                .frame(width: 2.5, height: 15)
                            Spacer()
                        }
                        .padding(.leading, -4)
                    }
                    .matchedGeometryEffect(id: "sidebar.selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Ortak sayfa iskeleti

struct PageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    var symbol: String
    var accent: Color
    var toolbar: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        if Snapshot.isRendering {
            stack.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { stack }.scrollIndicators(.never)
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.12), in: .rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(accent.opacity(0.25), lineWidth: 0.7)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let toolbar { toolbar }
            }
            .padding(.top, 26)

            content
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
    }
}
