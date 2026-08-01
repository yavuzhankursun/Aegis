import SwiftUI

struct StorageView: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        PageScaffold(
            title: "Depolama",
            subtitle: "Birim doluluk oranları ve kullanıcı klasörlerinin gerçek boyutu",
            symbol: "internaldrive",
            accent: Theme.violet,
            toolbar: AnyView(rescanButton)
        ) {
            ForEach(monitor.volumes) { volume in
                VolumeCard(volume: volume)
            }
            categoriesCard
            tipsCard
        }
        .onAppear {
            if monitor.storageCategories.isEmpty { monitor.scanStorageCategories() }
        }
    }

    private var rescanButton: some View {
        Button {
            monitor.refreshVolumes()
            monitor.scanStorageCategories()
        } label: {
            Label(monitor.isScanningStorage ? "Taranıyor…" : "Yeniden tara", systemImage: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(monitor.isScanningStorage)
    }

    private var categoriesCard: some View {
        GlassSection(title: "Klasör Boyutları", symbol: "folder", accent: Theme.violet) {
            if monitor.isScanningStorage && monitor.storageCategories.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Kullanıcı klasörleri taranıyor — erişim izni olmayan yerler atlanıyor.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
            } else if monitor.storageCategories.isEmpty {
                Text("Henüz tarama yapılmadı.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                let maxBytes = Double(monitor.storageCategories.first?.bytes ?? 1)
                VStack(spacing: 12) {
                    ForEach(monitor.storageCategories) { category in
                        HStack(spacing: 12) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.violet)
                                .frame(width: 24, height: 24)
                                .background(Theme.violet.opacity(0.14), in: .rect(cornerRadius: 7))

                            Text(category.name)
                                .font(.system(size: 12.5, weight: .medium))
                                .frame(width: 110, alignment: .leading)

                            MeterBar(fraction: Double(category.bytes) / max(maxBytes, 1),
                                     gradient: Theme.gradient([Theme.violet, Theme.indigo]),
                                     height: 7)

                            Text(Format.bytes(category.bytes))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .frame(width: 90, alignment: .trailing)
                        }
                    }

                    Text("Not: “Kitaplık” içindeki önbellekleri Temizlik sekmesinden güvenle boşaltabilirsin. "
                         + "Bazı sistem klasörleri Tam Disk Erişimi olmadan okunamaz ve toplama dahil edilmez.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var tipsCard: some View {
        GlassSection(title: "Yer Açma İpuçları", symbol: "lightbulb", accent: Theme.amber) {
            VStack(alignment: .leading, spacing: 9) {
                tip("Önbellekler ve derleme çıktıları genelde en hızlı kazançtır — Temizlik sekmesine bak.")
                tip("macOS'un kendi 'Purgeable' alanı vardır: iCloud'a yüklenmiş dosyalar disk dolunca otomatik boşaltılır. Bu yüzden 'Kullanılabilir' değeri boş alandan yüksek görünebilir.")
                tip("Disk %90'ı geçtiğinde APFS anlık görüntüleri ve takas alanı sıkışır; sistem gözle görülür yavaşlar.")
                tip("Time Machine yerel anlık görüntüleri disk dolunca kendiliğinden temizlenir — elle silmeye gerek yok.")
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.amber)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct VolumeCard: View {
    let volume: VolumeInfo

    var body: some View {
        GlassCard(tint: Theme.usageColor(volume.usedFraction)) {
            HStack(spacing: 22) {
                RingGauge(
                    fraction: volume.usedFraction,
                    gradient: Theme.gradient([Theme.usageColor(volume.usedFraction),
                                              Theme.usageColor(volume.usedFraction).opacity(0.45)]),
                    lineWidth: 10
                ) {
                    Text("\(Int(volume.usedFraction * 100))%")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(volume.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Pill(text: volume.isInternal ? "Dahili" : "Harici",
                             color: volume.isInternal ? Theme.aqua : Theme.violet,
                             symbol: volume.isInternal ? "internaldrive" : "externaldrive")
                        Pill(text: volume.fileSystem, color: Theme.textSecondary)
                        Spacer()
                    }

                    MeterBar(fraction: volume.usedFraction,
                             gradient: Theme.gradient([Theme.usageColor(volume.usedFraction),
                                                       Theme.usageColor(volume.usedFraction).opacity(0.6)]),
                             height: 9)

                    HStack(spacing: 26) {
                        StatBlock(value: Format.bytes(volume.usedBytes), label: "Kullanılan", size: 15)
                        StatBlock(value: Format.bytes(volume.freeBytes), label: "Boş alan", size: 15)
                        StatBlock(value: Format.bytes(volume.availableForImportantBytes),
                                  label: "Kullanılabilir (boşaltılabilir dahil)", color: Theme.teal, size: 15)
                        StatBlock(value: Format.bytes(volume.totalBytes), label: "Kapasite", size: 15)
                    }

                    if volume.availableForImportantBytes > volume.freeBytes {
                        let purgeable = volume.availableForImportantBytes - volume.freeBytes
                        Text("Kullanılan + Boş = Kapasite. “Kullanılabilir” bundan \(Format.bytes(purgeable)) "
                             + "fazladır çünkü macOS'un gerektiğinde boşaltabileceği alanı (iCloud'a yüklenmiş "
                             + "dosyalar, anlık görüntüler, önbellekler) da sayar.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(volume.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}
