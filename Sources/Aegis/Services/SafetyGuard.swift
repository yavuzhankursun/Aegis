import Foundation

/// Silme işlemlerinin tek kapısı.
///
/// Kural: bir yol, **izin verilen köklerden birinin gerçek alt öğesi** değilse
/// hiçbir koşulda dokunulmaz. Kökün kendisi de silinemez — sadece içindekiler.
/// Doğrulama sembolik bağlar çözüldükten sonra yapılır, böylece
/// `~/Library/Caches/kotu -> /` gibi bir tuzak işe yaramaz.
enum SafetyGuard {

    enum Verdict: Equatable, Sendable {
        case allowed
        case denied(String)

        var isAllowed: Bool { self == .allowed }
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()

    /// Silmeye izin verilen kökler. Bu listenin dışında hiçbir şey silinemez.
    static let allowedRoots: [URL] = {
        let h = home
        let library = h.appendingPathComponent("Library")
        return [
            library.appendingPathComponent("Caches"),
            library.appendingPathComponent("Logs"),
            library.appendingPathComponent("Developer/Xcode/DerivedData"),
            library.appendingPathComponent("Developer/Xcode/Archives"),
            library.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
            library.appendingPathComponent("Developer/CoreSimulator/Caches"),
            library.appendingPathComponent("Application Support/CrashReporter"),
            library.appendingPathComponent("Logs/DiagnosticReports"),
            library.appendingPathComponent("Containers"),
            library.appendingPathComponent("Group Containers"),
            library.appendingPathComponent("Application Support/MobileSync/Backup"),
            // Kalıntı Avcısı bölgeleri — yalnızca ters-DNS isimli girdiler için (aşağıda zorlanır).
            library.appendingPathComponent("Application Support"),
            library.appendingPathComponent("Preferences"),
            library.appendingPathComponent("Saved Application State"),
            library.appendingPathComponent("HTTPStorages"),
            library.appendingPathComponent("WebKit"),
            h.appendingPathComponent(".Trash"),
            h.appendingPathComponent(".npm/_cacache"),
            h.appendingPathComponent(".cache"),
            h.appendingPathComponent("Downloads"),
            h.appendingPathComponent("Library/Caches/Homebrew"),
        ].map { $0.standardizedFileURL }
    }()

    /// Asla dokunulmayacak yollar — izinli kökün altına düşseler bile.
    static let forbiddenExact: Set<String> = {
        let h = home
        var set = Set(allowedRoots.map { $0.path })
        set.insert(h.path)
        set.insert("/")
        for name in ["Documents", "Desktop", "Pictures", "Movies", "Music",
                     "Library", "Applications", "Public", "Developer"] {
            set.insert(h.appendingPathComponent(name).path)
        }
        return set
    }()

    /// Yol parçası olarak görülürse reddedilen bölgeler.
    static let forbiddenPrefixes: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library/Apple",
        home.appendingPathComponent("Library/Mobile Documents").path,   // iCloud Drive
        home.appendingPathComponent("Library/Keychains").path,
        home.appendingPathComponent("Library/Messages").path,
        home.appendingPathComponent("Library/Mail").path,
        home.appendingPathComponent("Library/Photos").path,
        home.appendingPathComponent("Library/Safari").path,
        home.appendingPathComponent("Library/Application Support/AddressBook").path,
    ]

    /// Container'lar içinde yalnızca `Caches` / `tmp` alt klasörlerine izin verilir.
    private static let containerRoots: Set<String> = [
        home.appendingPathComponent("Library/Containers").path,
        home.appendingPathComponent("Library/Group Containers").path,
    ]

    /// Bu köklerde **yalnızca** ters-DNS isimli (yani bir uygulamaya ait olduğu
    /// kesin) doğrudan çocuklar silinebilir. `Application Support/MyNotes` gibi
    /// serbest isimli klasörler — yani gerçek kullanıcı verisi — reddedilir.
    private static let reverseDNSOnlyRoots: Set<String> = [
        home.appendingPathComponent("Library/Application Support").path,
        home.appendingPathComponent("Library/Preferences").path,
        home.appendingPathComponent("Library/Saved Application State").path,
        home.appendingPathComponent("Library/HTTPStorages").path,
        home.appendingPathComponent("Library/WebKit").path,
    ]

    static func verify(_ url: URL) -> Verdict {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let path = resolved.path

        guard path.hasPrefix("/") else { return .denied("Göreli yol") }
        guard !path.contains("/../") else { return .denied("Geçersiz yol bileşeni") }
        guard path.count > 1 else { return .denied("Kök dizin") }
        guard forbiddenExact.contains(path) == false else { return .denied("Korunan dizinin kendisi") }

        for prefix in forbiddenPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return .denied("Korunan bölge: \(prefix)")
        }

        guard let root = allowedRoots.first(where: { path.hasPrefix($0.path + "/") }) else {
            return .denied("İzin verilen alanların dışında")
        }

        // Container'larda üç durum silinebilir:
        // 1) Önbellek/tmp alt ağaçları. Eşleşme SEGMENT sınırında yapılır:
        //    `contains("/Data/Library/Caches")` gibi bir alt-dize kontrolü
        //    `.../Data/Library/CachesEvil` adlı gerçek uygulama verisini de geçirirdi.
        // 2) Kalıntı Avcısı'nın bulduğu sahipsiz container'ın KENDİSİ —
        //    yalnızca kökün doğrudan çocuğu ve ters-DNS isimliyse.
        if containerRoots.contains(root.path) {
            let relative = String(path.dropFirst(root.path.count + 1))
            let isDirectChild = !relative.contains("/")
            let allowedSegment = hasSegment(relative, "Data/Library/Caches")
                || hasSegment(relative, "Library/Caches")
                || hasSegment(relative, "Data/tmp")
                || (isDirectChild && LeftoverService.isReverseDNS(relative))
            guard allowedSegment else { return .denied("Container içinde yalnızca önbellek silinebilir") }
        }

        // Kalıntı bölgeleri: sadece kökün doğrudan çocuğu ve ters-DNS isimli olabilir.
        if reverseDNSOnlyRoots.contains(root.path) {
            let relative = String(path.dropFirst(root.path.count + 1))
            guard !relative.contains("/") else { return .denied("Yalnızca üst düzey kalıntılar") }
            var name = relative
            for suffix in [".savedState", ".plist", ".binarycookies"] where name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
            }
            guard LeftoverService.isReverseDNS(name) else {
                return .denied("Uygulama kimliği biçiminde değil — kullanıcı verisi olabilir")
            }
        }

        return .allowed
    }

    /// `relative` yol dizisinde `segment`'i **tam bileşen sınırlarıyla** arar.
    /// `Data/Library/Caches` verildiğinde `.../Data/Library/Caches` ve
    /// `.../Data/Library/Caches/x` eşleşir; `.../Data/Library/CachesEvil` eşleşmez.
    private static func hasSegment(_ relative: String, _ segment: String) -> Bool {
        let hay = "/" + relative + "/"
        return hay.contains("/" + segment + "/")
    }

    /// Öğe zaten Çöp Kutusu'ndaysa "çöpe taşı" anlamsızdır; kalıcı silme gerekir.
    static func isInsideTrash(_ url: URL) -> Bool {
        let trash = home.appendingPathComponent(".Trash").path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix(trash + "/")
    }
}
