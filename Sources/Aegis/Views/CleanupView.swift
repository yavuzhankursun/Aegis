import SwiftUI
import AppKit

struct CleanupView: View {
    @Environment(CleanupStore.self) private var store
    @State private var showConfirm = false

    var body: some View {
        PageScaffold(
            title: "Temizlik",
            subtitle: "Geri kazanılabilir alanı bul — öğeler Çöp Kutusu'na taşınır, oradan geri alabilirsin",
            symbol: "sparkles",
            accent: Theme.orange,
            toolbar: AnyView(scanButton)
        ) {
            summaryCard
            if store.isScanning { scanProgress }
            if let result = store.lastResult { resultBanner(result) }
            ForEach(store.targets) { target in
                TargetCard(target: target)
            }
            if !store.isScanning && store.targets.isEmpty {
                emptyState
            }
            safetyCard
        }
        .confirmationDialog(
            "\(store.selectedItems.count) öğe temizlensin mi?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(store.selectionContainsPermanent ? "Taşı ve Kalıcı Sil" : "Çöp Kutusu'na Taşı",
                   role: .destructive) {
                store.clean()
            }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        var text = "\(Format.bytes(store.selectedBytes)) yer açılacak. "
        text += "Öğeler Çöp Kutusu'na taşınır; fikrin değişirse Finder'dan geri koyabilirsin."
        if store.selectionContainsPermanent {
            text += "\n\nDİKKAT: Seçimde zaten Çöp Kutusu'nda olan öğeler var. Onlar KALICI olarak silinecek ve geri alınamayacak."
        }
        return text
    }

    // MARK: - Üst

    private var scanButton: some View {
        HStack(spacing: 8) {
            if let lastScan = store.lastScan {
                Text(lastScan.formatted(date: .omitted, time: .shortened) + " tarandı")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Button {
                store.scan()
            } label: {
                Label(store.isScanning ? "Taranıyor…" : "Tara", systemImage: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(store.isScanning || store.isCleaning)
        }
    }

    private var summaryCard: some View {
        GlassCard(tint: Theme.rose) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Geri kazanılabilir")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(Format.bytes(store.totalFound))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.gradient([Theme.cyan, Theme.steel]))
                }

                Divider().frame(height: 52).opacity(0.25)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Seçili")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(Format.bytes(store.selectedBytes))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("\(store.selectedItems.count) öğe")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                VStack(spacing: 8) {
                    Button {
                        showConfirm = true
                    } label: {
                        Label(store.isCleaning ? "Temizleniyor…" : "Çöp Kutusu'na Taşı",
                              systemImage: "trash")
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.orange)
                    .disabled(store.selectedItems.isEmpty || store.isCleaning || store.isScanning)

                    HStack(spacing: 8) {
                        Button("Güvenlileri seç") { store.selectSafeOnly() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.aqua)
                        Text("•").foregroundStyle(Theme.textTertiary).font(.system(size: 9))
                        Button("Seçimi temizle") { store.clearSelection() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private var scanProgress: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Taranıyor: \(store.progressLabel)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(store.progress * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                MeterBar(fraction: store.progress,
                         gradient: Theme.gradient([Theme.cyan, Theme.steel]),
                         height: 7)
            }
        }
    }

    private func resultBanner(_ result: CleanupResult) -> some View {
        GlassCard(tint: result.failures.isEmpty ? Theme.mint : Theme.amber) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: result.failures.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(result.failures.isEmpty ? Theme.mint : Theme.amber)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(result.trashedCount) öğe temizlendi • \(Format.bytes(result.freedBytes)) yer açıldı")
                        .font(.system(size: 13, weight: .semibold))
                    if result.failures.isEmpty {
                        Text("Öğeler Çöp Kutusu'nda. Emin olana kadar boşaltmasan da olur.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(Array(result.failures.prefix(5)), id: \.self) { failure in
                            Text("• " + failure)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .thin))
                    .foregroundStyle(Theme.gradient([Theme.cyan, Theme.steel]))
                Text("Henüz tarama yapılmadı")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("“Tara” düğmesi önbellekleri, günlükleri, derleme çıktılarını ve eski indirmeleri "
                     + "kontrol eder. Hiçbir şey senin onayın olmadan taşınmaz.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
    }

    private var safetyCard: some View {
        GlassSection(title: "Güvenlik Modeli", symbol: "lock.shield", accent: Theme.mint) {
            VStack(alignment: .leading, spacing: 9) {
                rule("Silme değil, taşıma",
                     "Her öğe FileManager.trashItem ile Çöp Kutusu'na gider ve Finder'dan geri konabilir. "
                     + "Tek istisna \"Çöp Kutusu\" hedefidir: orada zaten çöpte olan öğeler kalıcı silinir "
                     + "ve onay penceresinde ayrıca uyarılırsın.")
                rule("Beyaz liste", "Yalnızca önbellek, günlük, derleme çıktısı gibi önceden tanımlı klasörlerin İÇİ taranır. Klasörün kendisi asla silinmez.")
                rule("Sembolik bağ koruması", "Yollar önce çözülür; bir kısayolun sistem dizinine işaret etmesi işe yaramaz.")
                rule("Yasak bölgeler", "Belgeler, iCloud Drive, Anahtar Zinciri, Mail, Fotoğraflar, /System ve /usr her koşulda reddedilir.")
                rule("Yükseltilmiş yetki yok", "Aegis sudo istemez, sistem dosyalarına dokunmaz, arka planda hiçbir şey çalıştırmaz.")
            }
        }
    }

    private func rule(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.mint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Hedef kartı

private struct TargetCard: View {
    @Environment(CleanupStore.self) private var store
    let target: CleanupTarget

    private var isExpanded: Bool { store.expanded.contains(target.id) }

    var body: some View {
        GlassCard(padding: 0, tint: target.risk == .review ? Theme.amber : Theme.steel) {
            VStack(spacing: 0) {
                header
                if isExpanded {
                    Divider().opacity(0.15)
                    itemList
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                store.toggleAll(in: target)
            } label: {
                Image(systemName: checkSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(store.selectionState(of: target) == .none ? .secondary : Theme.rose)
            }
            .buttonStyle(.plain)

            Image(systemName: target.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(target.risk == .safe ? Theme.mint : Theme.amber)
                .frame(width: 28, height: 28)
                .background((target.risk == .safe ? Theme.mint : Theme.amber).opacity(0.14),
                            in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(target.title)
                        .font(.system(size: 13.5, weight: .semibold))
                    Pill(text: target.risk.rawValue,
                         color: target.risk == .safe ? Theme.mint : Theme.amber,
                         symbol: target.risk == .safe ? "checkmark.shield" : "exclamationmark.triangle")
                }
                Text(target.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.bytes(target.totalBytes))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("\(target.items.count) öğe")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }

            Button {
                withAnimation(.smooth(duration: 0.24)) {
                    if isExpanded { store.expanded.remove(target.id) } else { store.expanded.insert(target.id) }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .buttonStyle(.plain)
            .frame(width: 22)
        }
        .padding(18)
        .contentShape(.rect)
    }

    private var checkSymbol: String {
        switch store.selectionState(of: target) {
        case .all: return "checkmark.circle.fill"
        case .partial: return "minus.circle.fill"
        case .none: return "circle"
        }
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            ForEach(target.items.prefix(40)) { item in
                HStack(spacing: 11) {
                    Button {
                        store.toggle(item)
                    } label: {
                        Image(systemName: store.isSelected(item) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(store.isSelected(item) ? Theme.cyan : Theme.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Text(item.displayName)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    if let modified = item.modified {
                        Text(Format.date(modified))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Text(Format.bytes(item.bytes))
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .frame(width: 76, alignment: .trailing)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Finder'da göster")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(store.isSelected(item) ? Theme.cyan.opacity(0.07) : .clear)
            }

            if target.items.count > 40 {
                Text("+ \(target.items.count - 40) öğe daha (seçim tümünü kapsar)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 8)
    }
}
