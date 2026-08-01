import SwiftUI
import AppKit

/// İlk açılışta gösterilen karşılama ve izin rehberi.
///
/// macOS'un izin diyalogları bağlamsızdır: kullanıcı "Aegis, Belgeler
/// klasörüne erişmek istiyor" uyarısını nedenini bilmeden görürse güven
/// kaybolur. Bu ekran her iznin **nedenini**, **ne zaman** isteneceğini ve
/// **verilmezse ne olacağını** önceden anlatır. Hiçbir izin zorunlu değildir;
/// uygulama izin verilmeyen yerleri sessizce atlar.
struct WelcomeView: View {
    let onFinish: () -> Void

    @State private var page = 0
    private static let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(28)

            footer
        }
        .frame(width: 720, height: 660)
        .background {
            ZStack {
                Rectangle().fill(Theme.void)
                // Sayfaya göre hafifçe kayan, STATİK vurgu ışıması —
                // animasyonlu cam yüzeyi yasağına (bkz. README) uyar.
                RadialGradient(colors: [accent.opacity(0.16), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 520)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var accent: Color {
        switch page {
        case 0: return Theme.cyan
        case 1: return Theme.amber
        default: return Theme.teal
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case 0: introPage
        case 1: permissionsPage
        default: safetyPage
        }
    }

    // MARK: - Sayfa 1 · Tanıtım

    private var introPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aegis'e hoş geldin")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Bu Mac'in kontrol merkezi — tek pencerede, tamamen salt okunur telemetri.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                      spacing: 12) {
                feature("battery.100percent.bolt", Theme.teal, "Pil",
                        "Sağlık, döngü ve gauge yongasının ömür boyu kaydı — hücre dengesi dahil.")
                feature("gauge.with.dots.needle.67percent", Theme.steel, "Performans",
                        "Activity Monitor ile aynı tanımlarla bellek dağılımı, baskı ve CPU yükü.")
                feature("bolt.horizontal", Theme.amber, "Enerji",
                        "macOS'un kendi Energy Impact ölçümüyle güç tüketen süreçler.")
                feature("internaldrive", Theme.plasma, "Depolama",
                        "Birim doluluğu ve kullanıcı klasörlerinin gerçek boyutu.")
                feature("sparkles", Theme.orange, "Temizlik",
                        "Önbellek, günlük ve kalıntı taraması — silme yok, yalnızca Çöp Kutusu'na taşıma.")
                feature("power", Theme.lime, "Başlangıç",
                        "Launch agent/daemon denetçisi; hedefi kaybolmuş hayalet ajanları yakalar.")
            }

            Spacer(minLength: 0)

            GlassCard(padding: 14, tint: Theme.teal, lifts: false) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ağ erişimi yok · yükseltilmiş yetki yok · veri toplama yok")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Kaynak kodu açık; silme kapısının kararları 36 durumluk öz denetimle sabitlenmiştir.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        GlassCard(padding: 13, lifts: false) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 27, height: 27)
                    .background(color.opacity(0.14), in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(text)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Sayfa 2 · İzinler

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHeader("hand.raised.fill", Theme.amber, "İzinler — neden ve ne için",
                       "Hiçbiri zorunlu değil. İzin vermediğin her yer sessizce atlanır; uygulama çalışmaya devam eder.")

            permission(
                symbol: "folder.fill", color: Theme.cyan,
                title: "Masaüstü, Belgeler ve İndirilenler",
                why: "Depolama sekmesi bu klasörlerin gerçek boyutunu hesaplar; Temizlik sekmesi "
                   + "İndirilenler'de 90 gündür dokunulmamış dosyaları aday olarak listeler.",
                when: "İlgili sekmeyi ilk açtığında macOS'un kendi diyaloğu sorar — Aegis bu diyaloğu tetikler, içeriğini görmez.",
                without: "O klasör boyut toplamlarına girmez, eski indirme önerisi çıkmaz. Başka hiçbir şey etkilenmez."
            )

            permission(
                symbol: "externaldrive.fill", color: Theme.plasma,
                title: "Harici diskler",
                why: "Depolama sekmesinde takılı disklerin doluluk oranını göstermek için.",
                when: "Harici disk takılıyken Depolama sekmesini ilk açtığında.",
                without: "Yalnızca dahili disk görünür."
            )

            permission(
                symbol: "internaldrive.fill", color: Theme.amber,
                title: "Tam Disk Erişimi — isteğe bağlı",
                why: "Kitaplık içindeki bazı korumalı klasörlerin (ör. posta önbellekleri) boyutunu "
                   + "okuyabilmek için. Aegis oralarda da yalnızca boyut sayar; içerik okumaz, silme "
                   + "kapısı posta/mesaj/anahtar zinciri bölgelerini her koşulda reddeder.",
                when: "macOS bu izni uygulamalara sordurtmaz: Sistem Ayarları'ndan kendin eklersin. İstersen hiç ekleme.",
                without: "Bazı klasör boyutları eksik görünür — hepsi bu.",
                action: ("Sistem Ayarları'nı Aç", {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                })
            )

            GlassCard(padding: 13, tint: Theme.teal, lifts: false) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "nosign")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.teal)
                        .frame(width: 27, height: 27)
                        .background(Theme.teal.opacity(0.14), in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hiç istemeyecekleri")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Ağ bağlantısı, konum, kamera/mikrofon, kişiler, analitik, yönetici parolası. "
                             + "Bunların hiçbiri kodda yok — istenmiyor değil, istenemiyor.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func permission(symbol: String, color: Color, title: String,
                            why: String, when: String, without: String,
                            action: (label: String, run: () -> Void)? = nil) -> some View {
        GlassCard(padding: 14, lifts: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 27, height: 27)
                        .background(color.opacity(0.14), in: .rect(cornerRadius: 8))
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    if let action {
                        Button(action.label, action: action.run)
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }
                detailRow("Neden", why, color)
                detailRow("Ne zaman", when, Theme.textSecondary)
                detailRow("Vermezsen", without, Theme.teal)
            }
        }
    }

    private func detailRow(_ label: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(color)
                .frame(width: 62, alignment: .trailing)
                .padding(.top, 1.5)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Sayfa 3 · Güvenlik modeli

    private var safetyPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHeader("lock.shield.fill", Theme.teal, "Mac'ine zarar veremez",
                       "Bu bir pazarlama cümlesi değil, tasarımın çıkış noktası. Nasıl çalıştığı:")

            safetyRow("trash.fill", Theme.cyan, "Silme yok, taşıma var",
                      "Temizlikte her öğe Çöp Kutusu'na taşınır ve Finder'dan geri konabilir. Tek istisna "
                      + "zaten çöpte olanlardır; orada kalıcı silme kaçınılmazdır ve ayrıca uyarılırsın.")
            safetyRow("checkmark.shield.fill", Theme.teal, "Tek kapı: SafetyGuard",
                      "Silinecek her yol iki kez güvenlik kapısından geçer. Belgeler, Fotoğraflar, iCloud, "
                      + "Anahtar Zinciri, Mail ve sistem dizinleri her koşulda reddedilir — kapının kararları "
                      + "36 durumluk öz denetimle sabitlenmiştir; tek komutla kendin doğrulayabilirsin.")
            safetyRow("hand.raised.slash.fill", Theme.amber, "Süreçlere sinyal gönderilmez",
                      "Bir uygulamayı kapatmak Cmd+Q ile aynıdır: kaydedilmemiş verin varsa uygulama sorar. "
                      + "Zorla öldürme yoktur; Finder ve Dock gibi sistem süreçleri iki katmanda korunur.")
            safetyRow("terminal.fill", Theme.plasma, "Kabuk yok, beyaz liste var",
                      "Dış araç çağrıları beş salt-okunur sistem aracıyla sınırlıdır (top, sysctl, "
                      + "system_profiler, csrutil, ioreg). /bin/sh hiç kullanılmaz — komut enjeksiyonu imkânsız.")

            Spacer(minLength: 0)

            GlassCard(padding: 14, tint: Theme.cyan, lifts: false) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.cyan)
                    Text("Hazırsın. Bu ekrana istediğin zaman **Yardım → Hoş Geldin Ekranını Göster** ile dönebilirsin.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func safetyRow(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        GlassCard(padding: 14, lifts: false) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.14), in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Ortak parçalar

    private func pageHeader(_ symbol: String, _ color: Color, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.14), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Atla") { onFinish() }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .opacity(page < Self.pageCount - 1 ? 1 : 0)
                .disabled(page >= Self.pageCount - 1)

            Spacer()

            HStack(spacing: 7) {
                ForEach(0..<Self.pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? accent : Color.white.opacity(0.18))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if page > 0 {
                    Button("Geri") { withAnimation(.easeOut(duration: 0.18)) { page -= 1 } }
                        .buttonStyle(.glass)
                }
                if page < Self.pageCount - 1 {
                    Button("Devam") { withAnimation(.easeOut(duration: 0.18)) { page += 1 } }
                        .buttonStyle(.glass)
                        .tint(accent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Başla") { onFinish() }
                        .buttonStyle(.glass)
                        .tint(Theme.teal)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.black.opacity(0.25))
        .overlay(alignment: .top) { Divider().opacity(0.25) }
    }
}
