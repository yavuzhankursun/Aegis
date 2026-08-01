import Foundation

/// Gereksiz dosya taraması ve **Çöp Kutusu'na taşıma** temelli temizlik.
///
/// Tasarım ilkeleri:
/// - Silme yok, taşıma var: her şey `FileManager.trashItem` ile çöpe gider (geri alınabilir).
///   Tek istisna zaten çöpteki öğeler — orada kalıcı silme kaçınılmaz ve kullanıcı bunu ister.
/// - Her öğe silinmeden önce ayrı ayrı `SafetyGuard`'dan geçer.
/// - Tarama süre sınırlıdır ve iptal edilebilir; asla uygulamayı kilitlemez.
struct CleanupService: Sendable {

    private var fm: FileManager { .default }
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: - Tarama

    func scan(budget: TimeInterval = 45, progress: (@Sendable (String, Double) -> Void)? = nil) -> [CleanupTarget] {
        let deadline = Date().addingTimeInterval(budget)
        let definitions = targetDefinitions()
        var results: [CleanupTarget] = []

        for (index, definition) in definitions.enumerated() {
            progress?(definition.title, Double(index) / Double(definitions.count))
            if Date() > deadline { break }

            let items = definition.collect(deadline)
            results.append(CleanupTarget(
                id: definition.id,
                title: definition.title,
                detail: definition.detail,
                symbol: definition.symbol,
                risk: definition.risk,
                items: items
            ))
        }

        progress?("Tamamlandı", 1.0)
        return results.sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - Temizlik

    /// Seçilen öğeleri çöpe taşır. Her öğe tek tek doğrulanır; biri reddedilirse
    /// diğerleri etkilenmez.
    func clean(items: [CleanupItem]) -> CleanupResult {
        var result = CleanupResult()

        for item in items {
            let verdict = SafetyGuard.verify(item.url)
            guard verdict.isAllowed else {
                if case let .denied(reason) = verdict {
                    result.failures.append("\(item.displayName): reddedildi — \(reason)")
                }
                continue
            }
            guard fm.fileExists(atPath: item.url.path) else { continue }

            // Tarama ile silme arasında öğe sembolik bağla değiştirilmiş olabilir.
            // Bağın kendisini taşımak zararsızdır ama yine de reddederiz:
            // son kapı, tarama katmanına güvenmeden tek başına sağlam olmalı.
            if let values = try? item.url.resourceValues(forKeys: [.isSymbolicLinkKey]),
               values.isSymbolicLink == true {
                result.failures.append("\(item.displayName): reddedildi — sembolik bağ")
                continue
            }

            do {
                if SafetyGuard.isInsideTrash(item.url) {
                    try fm.removeItem(at: item.url)
                } else {
                    var resulting: NSURL?
                    try fm.trashItem(at: item.url, resultingItemURL: &resulting)
                }
                result.trashedCount += 1
                result.freedBytes &+= item.bytes
            } catch {
                result.failures.append("\(item.displayName): \(error.localizedDescription)")
            }
        }

        return result
    }

    // MARK: - Hedef tanımları

    private struct Definition {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let risk: CleanupRisk
        let collect: @Sendable (Date) -> [CleanupItem]
    }

    private func targetDefinitions() -> [Definition] {
        let library = home.appendingPathComponent("Library")

        return [
            Definition(
                id: "user-caches",
                title: "Uygulama Önbellekleri",
                detail: "~/Library/Caches — uygulamalar gerektiğinde yeniden oluşturur.",
                symbol: "shippingbox",
                risk: .safe,
                collect: { deadline in
                    children(of: library.appendingPathComponent("Caches"), deadline: deadline)
                }
            ),
            Definition(
                id: "logs",
                title: "Uygulama Günlükleri",
                detail: "~/Library/Logs — eski hata ve olay kayıtları.",
                symbol: "doc.text.magnifyingglass",
                risk: .safe,
                collect: { deadline in
                    children(of: library.appendingPathComponent("Logs"), deadline: deadline)
                }
            ),
            Definition(
                id: "crash-reports",
                title: "Çökme Raporları",
                detail: "Tanılama raporları — sorun gidermeyi bitirdiysen gereksiz.",
                symbol: "exclamationmark.triangle",
                risk: .safe,
                collect: { deadline in
                    children(of: library.appendingPathComponent("Application Support/CrashReporter"), deadline: deadline)
                }
            ),
            Definition(
                id: "xcode-derived",
                title: "Xcode DerivedData",
                detail: "Derleme çıktıları — bir sonraki derlemede yeniden üretilir.",
                symbol: "hammer",
                risk: .safe,
                collect: { deadline in
                    children(of: library.appendingPathComponent("Developer/Xcode/DerivedData"), deadline: deadline)
                }
            ),
            Definition(
                id: "simulator-caches",
                title: "Simulator Önbelleği",
                detail: "CoreSimulator önbellekleri ve indirilen çalışma zamanları.",
                symbol: "iphone",
                risk: .safe,
                collect: { deadline in
                    children(of: library.appendingPathComponent("Developer/CoreSimulator/Caches"), deadline: deadline)
                }
            ),
            Definition(
                id: "device-support",
                title: "Xcode Aygıt Desteği",
                detail: "Eski iOS sürümleri için sembol dosyaları. O cihazlarla artık çalışmıyorsan silinebilir.",
                symbol: "externaldrive.badge.xmark",
                risk: .review,
                collect: { deadline in
                    children(of: library.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"), deadline: deadline)
                }
            ),
            Definition(
                id: "package-caches",
                title: "Paket Yöneticisi Önbellekleri",
                detail: "npm, pip, Homebrew ve benzeri indirme önbellekleri.",
                symbol: "cube.box",
                risk: .safe,
                collect: { deadline in
                    var items: [CleanupItem] = []
                    items += children(of: home.appendingPathComponent(".npm/_cacache"), deadline: deadline)
                    items += children(of: home.appendingPathComponent(".cache"), deadline: deadline)
                    items += children(of: library.appendingPathComponent("Caches/Homebrew"), deadline: deadline)
                    return items
                }
            ),
            Definition(
                id: "container-caches",
                title: "Sandbox Uygulama Önbellekleri",
                detail: "App Store uygulamalarının kendi önbellek klasörleri.",
                symbol: "square.stack.3d.up",
                risk: .safe,
                collect: { deadline in containerCaches(deadline: deadline) }
            ),
            Definition(
                id: "leftovers",
                title: "Kaldırılan Uygulama Kalıntıları",
                detail: "Artık kurulu olmayan uygulamaların geride bıraktığı ayar, önbellek ve container'lar.",
                symbol: "questionmark.app.dashed",
                risk: .review,
                collect: { deadline in LeftoverService().scan(deadline: deadline) }
            ),
            Definition(
                id: "old-downloads",
                title: "Eski İndirilenler",
                detail: "90 günden uzun süredir dokunulmamış indirmeler.",
                symbol: "arrow.down.circle",
                risk: .review,
                collect: { deadline in
                    oldItems(in: home.appendingPathComponent("Downloads"), olderThanDays: 90, deadline: deadline)
                }
            ),
            Definition(
                id: "ios-backups",
                title: "iPhone / iPad Yedekleri",
                detail: "Yerel aygıt yedekleri. iCloud yedeğin varsa gereksiz olabilir — dikkatli seç.",
                symbol: "iphone.gen3",
                risk: .review,
                collect: { deadline in
                    children(of: library.appendingPathComponent("Application Support/MobileSync/Backup"), deadline: deadline)
                }
            ),
            Definition(
                id: "trash",
                title: "Çöp Kutusu",
                detail: "Zaten çöpteki öğeler. Buradan silme KALICIDIR.",
                symbol: "trash",
                risk: .review,
                collect: { deadline in
                    children(of: home.appendingPathComponent(".Trash"), deadline: deadline)
                }
            ),
        ]
    }
}

// MARK: - Toplayıcılar (Sendable closure'lardan çağrılabilmesi için serbest fonksiyon)

private func children(of directory: URL, deadline: Date) -> [CleanupItem] {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }

    let keys: [URLResourceKey] = [.isSymbolicLinkKey, .contentModificationDateKey, .isDirectoryKey]
    guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                    includingPropertiesForKeys: keys,
                                                    options: [.skipsHiddenFiles]) else { return [] }

    var items: [CleanupItem] = []
    for entry in entries {
        if Date() > deadline { break }
        guard SafetyGuard.verify(entry).isAllowed else { continue }

        let values = try? entry.resourceValues(forKeys: Set(keys))
        if values?.isSymbolicLink == true { continue }

        let size = FileSizer.size(of: entry, deadline: deadline)
        guard size > 0 else { continue }

        items.append(CleanupItem(
            url: entry,
            bytes: size,
            displayName: entry.lastPathComponent,
            modified: values?.contentModificationDate
        ))
    }
    return items.sorted { $0.bytes > $1.bytes }
}

private func containerCaches(deadline: Date) -> [CleanupItem] {
    let fm = FileManager.default
    let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers")
    guard let containers = try? fm.contentsOfDirectory(at: root,
                                                       includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles]) else { return [] }

    var items: [CleanupItem] = []
    for container in containers {
        if Date() > deadline { break }
        let cacheDirectory = container.appendingPathComponent("Data/Library/Caches")
        guard fm.fileExists(atPath: cacheDirectory.path) else { continue }
        let size = FileSizer.size(of: cacheDirectory, deadline: deadline)
        guard size > 4 * 1024 * 1024 else { continue }   // 4 MB altını gösterme, gürültü
        guard SafetyGuard.verify(cacheDirectory).isAllowed else { continue }

        items.append(CleanupItem(
            url: cacheDirectory,
            bytes: size,
            displayName: container.lastPathComponent,
            modified: nil
        ))
    }
    return items.sorted { $0.bytes > $1.bytes }
}

/// Bir dizinin kendi `mtime`'ı yalnızca doğrudan girdisi eklenip silinince değişir;
/// içindeki bir dosya düzenlenirse değişmez. Bu yüzden klasörler için
/// **içerideki en yeni** değişiklik tarihine bakarız — aktif kullanılan bir proje
/// klasörü "90 gündür dokunulmamış" diye listelenmesin.
private func newestModification(of url: URL, deadline: Date) -> Date? {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .isSymbolicLinkKey]
    guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
    if values.isSymbolicLink == true { return nil }
    guard values.isDirectory == true else { return values.contentModificationDate }

    var newest = values.contentModificationDate
    guard let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles],
        errorHandler: { _, _ in true }
    ) else { return newest }

    var checked = 0
    for case let child as URL in enumerator {
        checked += 1
        if checked % 256 == 0, Date() > deadline { break }
        guard let date = try? child.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else { continue }
        if newest == nil || date > newest! { newest = date }
    }
    return newest
}

private func oldItems(in directory: URL, olderThanDays days: Int, deadline: Date) -> [CleanupItem] {
    let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
    return children(of: directory, deadline: deadline).compactMap { item in
        guard let newest = newestModification(of: item.url, deadline: deadline),
              newest < cutoff else { return nil }
        return CleanupItem(url: item.url, bytes: item.bytes,
                           displayName: item.displayName, modified: newest)
    }
}
