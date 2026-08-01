import Foundation

/// Açılışta arka planda çalışan ajan ve daemon'ları listeler.
/// Tamamen **salt okunur**: hiçbir plist değiştirilmez, `launchctl` çağrılmaz.
/// Öne çıkardığı asıl değer, hedef programı artık var olmayan
/// "hayalet" ajanları yakalamasıdır.
struct StartupItem: Identifiable, Equatable, Sendable {
    var id: String { path }
    let label: String
    let path: String
    let program: String
    let scope: Scope
    let runAtLoad: Bool
    let keepAlive: Bool
    let programExists: Bool
    let isApple: Bool

    enum Scope: String, Sendable {
        case userAgent = "Kullanıcı Ajanı"
        case globalAgent = "Sistem Ajanı"
        case daemon = "Daemon (root)"
    }

    /// Hedef program mutlak bir yol olarak tanımlanmış ama diskte yok.
    var isGhost: Bool { !programExists && program.hasPrefix("/") }
}

struct StartupService: Sendable {

    func scan() -> [StartupItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sources: [(URL, StartupItem.Scope)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
        ]

        var items: [StartupItem] = []
        for (directory, scope) in sources {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "plist" {
                guard let item = parse(file, scope: scope) else { continue }
                items.append(item)
            }
        }

        // Hayaletler önce, sonra Apple dışı, sonra alfabetik.
        return items.sorted { lhs, rhs in
            if lhs.isGhost != rhs.isGhost { return lhs.isGhost }
            if lhs.isApple != rhs.isApple { return !lhs.isApple }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private func parse(_ url: URL, scope: StartupItem.Scope) -> StartupItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let label = (plist["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent

        var program = plist["Program"] as? String ?? ""
        if program.isEmpty, let arguments = plist["ProgramArguments"] as? [String], let first = arguments.first {
            program = first
        }

        // Yalnızca mutlak yol iddiası doğrulanabilir. `open`, `bash` gibi
        // PATH üzerinden çözülen komutlar "kayıp" sayılmaz.
        let isAbsolutePath = program.hasPrefix("/")
        let exists = !isAbsolutePath || FileManager.default.fileExists(atPath: program)

        // "Apple" rozeti için etiket YETMEZ: herhangi bir ajan kendine
        // `com.apple.evil` etiketi verebilir. Programın gerçekten Apple'a ait
        // bir bölgede durması da gerekir; aksi halde rozet kamuflaj olurdu.
        let appleLabel = label.lowercased().hasPrefix("com.apple.")
        let appleTerritory = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"]
        let appleProgram = program.isEmpty || appleTerritory.contains { program.hasPrefix($0) }

        return StartupItem(
            label: label,
            path: url.path,
            program: program,
            scope: scope,
            runAtLoad: (plist["RunAtLoad"] as? Bool) ?? false,
            keepAlive: plist["KeepAlive"] != nil,
            programExists: exists,
            isApple: appleLabel && appleProgram
        )
    }
}
