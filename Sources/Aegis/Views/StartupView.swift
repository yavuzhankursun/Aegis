import SwiftUI
import AppKit

/// Açılışta çalışan ajan/daemon denetçisi.
/// Piyasadaki temizlik uygulamaları genelde bunları sadece sayar;
/// burada asıl amaç **hedefi kaybolmuş "hayalet" ajanları** ortaya çıkarmak.
struct StartupView: View {
    @Environment(SystemMonitor.self) private var monitor
    @State private var hideApple = true

    private var items: [StartupItem] {
        hideApple ? monitor.startupItems.filter { !$0.isApple } : monitor.startupItems
    }

    private var ghosts: [StartupItem] { monitor.startupItems.filter(\.isGhost) }

    var body: some View {
        PageScaffold(
            title: "Başlangıç",
            subtitle: "Mac açılırken arka planda başlayan ajanlar ve daemon'lar",
            symbol: "power",
            accent: Theme.lime,
            toolbar: AnyView(toolbar)
        ) {
            summaryRow
            if !ghosts.isEmpty { ghostCard }
            listCard
            noteCard
        }
        .onAppear { monitor.refreshStartupItems() }
    }

    private var toolbar: some View {
        Toggle("Apple bileşenlerini gizle", isOn: $hideApple)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
    }

    private var summaryRow: some View {
        HStack(spacing: 16) {
            metric("\(monitor.startupItems.count)", "Toplam öğe", "list.bullet", Theme.lime)
            metric("\(monitor.startupItems.filter { !$0.isApple }.count)", "Üçüncü taraf", "shippingbox", Theme.cyan)
            metric("\(monitor.startupItems.filter { $0.scope == .daemon }.count)", "Root daemon", "shield.lefthalf.filled", Theme.amber)
            metric("\(ghosts.count)", "Hayalet ajan", "questionmark.diamond",
                   ghosts.isEmpty ? Theme.teal : Theme.crimson)
        }
    }

    private func metric(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        GlassCard(tint: color) {
            StatBlock(value: value, label: label, symbol: symbol, color: color, size: 26)
        }
    }

    private var ghostCard: some View {
        GlassSection(title: "Hayalet Ajanlar", symbol: "questionmark.diamond.fill", accent: Theme.crimson) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bu tanımların işaret ettiği program artık diskte yok. Genellikle düzgün kaldırılmamış "
                     + "uygulamalardan kalır; her açılışta launchd bunları boşuna dener.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(ghosts) { item in
                    StartupRow(item: item)
                    if item.id != ghosts.last?.id { Divider().opacity(0.12) }
                }
            }
        }
    }

    private var listCard: some View {
        GlassSection(title: "Tüm Başlangıç Öğeleri", symbol: "power", accent: Theme.lime) {
            if items.isEmpty {
                Text(monitor.startupItems.isEmpty ? "Taranıyor…" : "Üçüncü taraf başlangıç öğesi yok. Temiz.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        StartupRow(item: item)
                        if item.id != items.last?.id { Divider().opacity(0.10) }
                    }
                }
            }
        }
    }

    private var noteCard: some View {
        GlassSection(title: "Neden Sadece Gösteriyorum?", symbol: "hand.raised", accent: Theme.teal) {
            VStack(alignment: .leading, spacing: 8) {
                bullet("Bir launch agent'ı devre dışı bırakmak, ona bağlı uygulamayı sessizce bozabilir (güncelleyici, VPN, yedekleme).")
                bullet("`/Library/LaunchDaemons` root yetkisiyle çalışır; oradaki bir dosyaya dokunmak sistem bütünlüğünü etkiler.")
                bullet("Aegis bu yüzden yalnızca listeler ve Finder'da gösterir. Kararı ve işlemi sen yaparsın.")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(Theme.teal).frame(width: 4, height: 4).padding(.top, 6)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct StartupRow: View {
    let item: StartupItem
    @State private var hovering = false

    private var scopeColor: Color {
        switch item.scope {
        case .userAgent: return Theme.cyan
        case .globalAgent: return Theme.steel
        case .daemon: return Theme.amber
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isGhost ? "questionmark.diamond.fill" : "circle.hexagongrid")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.isGhost ? Theme.crimson : scopeColor)
                .frame(width: 24, height: 24)
                .background((item.isGhost ? Theme.crimson : scopeColor).opacity(0.13), in: .rect(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(item.label)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    if item.isApple { Pill(text: "Apple", color: Theme.textTertiary) }
                    if item.runAtLoad { Pill(text: "açılışta", color: scopeColor) }
                    if item.keepAlive { Pill(text: "sürekli", color: Theme.amber) }
                }
                Text(item.program.isEmpty ? item.path : item.program)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(item.isGhost ? Theme.crimson.opacity(0.85) : Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Pill(text: item.scope.rawValue, color: scopeColor)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(hovering ? Theme.text : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Finder'da göster")
        }
        .padding(.vertical, 7)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .background(hovering ? Color.white.opacity(0.04) : .clear)
    }
}
