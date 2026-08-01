import Foundation
import AppKit

/// **Kalıntı Avcısı** — silinmiş uygulamaların geride bıraktığı
/// ayar, önbellek, container ve durum dosyalarını bulur.
///
/// Yöntem: diskteki tüm `.app` paketlerinin bundle kimlikleri toplanır,
/// ardından kalıntı klasörlerindeki ters-DNS isimli girdiler bu kümeyle
/// karşılaştırılır. Kümede olmayan → sahipsiz kalıntı.
struct LeftoverService: Sendable {

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Kalıntıların aranacağı yerler ve dosya biçimleri.
    private var residenceRoots: [(URL, String)] {
        let library = home.appendingPathComponent("Library")
        return [
            (library.appendingPathComponent("Application Support"), "klasör"),
            (library.appendingPathComponent("Containers"), "container"),
            (library.appendingPathComponent("Caches"), "önbellek"),
            (library.appendingPathComponent("Preferences"), "ayar"),
            (library.appendingPathComponent("Saved Application State"), "pencere durumu"),
            (library.appendingPathComponent("HTTPStorages"), "çerez/depo"),
            (library.appendingPathComponent("WebKit"), "web verisi"),
            (library.appendingPathComponent("Logs"), "günlük"),
        ]
    }

    /// Bu süreden yakın zamanda değişmiş kalıntılar "sahipsiz" sayılmaz:
    /// canlı bir uygulama destek klasörüne yazıyordur.
    private static let staleThreshold: TimeInterval = 90 * 86400

    func scan(deadline: Date) -> [CleanupItem] {
        let installed = installedBundleIdentifiers()
        guard installed.count > 5 else { return [] }   // tarama başarısızsa hiçbir şey önerme

        // Kurulu kimliklerin satıcı önekleri (`com.google.`, `com.adobe.` …).
        // Bir uygulamanın yardımcıları, güncelleyicileri ve XPC servisleri kendi
        // ayrı kimlikleriyle klasör açar; bunlar .app listesinde görünmez ama
        // sahibi kurulu olduğu için kalıntı DEĞİLDİR.
        let vendorPrefixes = Set(installed.compactMap { identifier -> String? in
            let parts = identifier.split(separator: ".")
            guard parts.count >= 2 else { return nil }
            return parts[0...1].joined(separator: ".") + "."
        })

        let cutoff = Date().addingTimeInterval(-Self.staleThreshold)
        var items: [CleanupItem] = []

        for (root, kind) in residenceRoots {
            if Date() > deadline { break }
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                if Date() > deadline { break }
                // Sembolik bağlar aday bile olamaz — hedefi başka yeri gösterebilir.
                if (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { continue }
                guard let identifier = bundleIdentifier(from: entry) else { continue }
                guard !installed.contains(identifier) else { continue }
                // Satıcısı kurulu olan hiçbir şeyi kalıntı ilan etme.
                guard !vendorPrefixes.contains(where: { identifier.hasPrefix($0) }) else { continue }
                guard SafetyGuard.verify(entry).isAllowed else { continue }

                let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                // Son 90 günde yazılmışsa arkasında çalışan bir şey var demektir.
                if let modified, modified > cutoff { continue }

                let size = FileSizer.size(of: entry, deadline: deadline)
                guard size > 64 * 1024 else { continue }   // önemsiz kırıntıları gösterme

                items.append(CleanupItem(
                    url: entry,
                    bytes: size,
                    displayName: "\(identifier)  ·  \(kind)",
                    modified: modified
                ))
            }
        }

        return items.sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Yardımcılar

    /// Girdinin adından bundle kimliği çıkarır. Ters-DNS görünmüyorsa `nil`.
    private func bundleIdentifier(from url: URL) -> String? {
        var name = url.lastPathComponent
        for suffix in [".savedState", ".plist", ".binarycookies"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return Self.isReverseDNS(name) ? name : nil
    }

    /// `com.firma.uygulama` biçimi: en az iki nokta, boşluk yok, Apple değil.
    static func isReverseDNS(_ name: String) -> Bool {
        guard name.filter({ $0 == "." }).count >= 2 else { return false }
        guard !name.contains(" "), !name.hasSuffix("."), !name.hasPrefix(".") else { return false }
        let lower = name.lowercased()
        // Apple ve sistem bileşenlerine asla dokunulmaz.
        for reserved in ["com.apple.", "group.com.apple", "systemgroup.", "com.microsoft.autoupdate"]
        where lower.hasPrefix(reserved) { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Kurulu tüm uygulamaların bundle kimlikleri.
    private func installedBundleIdentifiers() -> Set<String> {
        var result = Set<String>()
        let roots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            home.appendingPathComponent("Applications").path,
            home.appendingPathComponent("Developer/Applications").path,
            "/Applications/Xcode.app/Contents/Applications",
        ]

        for root in roots {
            collectApps(in: URL(fileURLWithPath: root), depth: 0, into: &result)
        }

        // Çalışan her şey kurulu sayılır (App Store dışı yollarda duran uygulamalar için emniyet).
        for app in NSWorkspace.shared.runningApplications {
            if let identifier = app.bundleIdentifier { result.insert(identifier) }
        }

        return result
    }

    /// Uygulama klasörlerini birkaç seviye derinlemesine tarar.
    /// Setapp (`/Applications/Setapp/*.app`), Adobe ve JetBrains Toolbox gibi
    /// kurulumlar uygulamaları alt klasörlerde tutar; tek seviyeli tarama
    /// bunları "kurulu değil" sanıp canlı verilerini kalıntı olarak işaretlerdi.
    private func collectApps(in directory: URL, depth: Int, into result: inout Set<String>) {
        guard depth <= 3 else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            if ["app", "xpc", "appex"].contains(entry.pathExtension) {
                if let identifier = Bundle(url: entry)?.bundleIdentifier {
                    result.insert(identifier)
                }
                // Gömülü yardımcılar ve giriş öğeleri kendi kimliklerini taşır.
                // `depth: 3` ile çağırıyoruz: bu klasörün bir seviyesi taranır, daha derine inilmez.
                for relative in ["Contents/Library/LoginItems",
                                 "Contents/Library/Helpers",
                                 "Contents/XPCServices",
                                 "Contents/PlugIns"] {
                    collectApps(in: entry.appendingPathComponent(relative), depth: 3, into: &result)
                }
                continue
            }
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                collectApps(in: entry, depth: depth + 1, into: &result)
            }
        }
    }
}
