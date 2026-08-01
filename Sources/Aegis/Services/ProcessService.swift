import Foundation
import AppKit
import Darwin

/// Çalışan süreçlerin CPU / enerji / bellek tüketimi.
///
/// `top`'un **power** sütunu macOS'un kendi "Energy Impact" ölçümüdür ve
/// root yetkisi gerektirmez. Süreçlere hiçbir sinyal gönderilmez;
/// sonlandırma yalnızca kullanıcı onayıyla ve yalnızca GUI uygulamaları için yapılır.
struct ProcessService: Sendable {

    func topProcesses(limit: Int = 200) -> [ProcessInfoRow] {
        // -l 2: ilk örnek referans, ikinci örnek gerçek delta değerlerini verir.
        // `limit` geniş tutulur: liste CPU'ya göre sıralı geldiğinden dar bir
        // limit, CPU'su düşük ama RAM'i yüksek süreçleri (tipik "bellek canavarı")
        // bellek sıralamasının hiç göremeyeceği şekilde keserdi.
        let out = Shell.run("/usr/bin/top",
                            ["-l", "2", "-n", "\(limit)", "-s", "1",
                             "-o", "cpu", "-stats", "pid,cpu,power,mem"],
                            timeout: 12)
        guard !out.stdout.isEmpty else { return [] }

        let apps = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app -> (Int32, NSRunningApplication)? in
                app.processIdentifier > 0 ? (app.processIdentifier, app) : nil
            },
            uniquingKeysWith: { first, _ in first }
        )

        var rows: [ProcessInfoRow] = []
        var seen = Set<Int32>()

        // Sadece **son** tablo başlığından sonraki satırları al.
        // Başlıktaki sütun genişliği en geniş PID'ye göre değiştiği için
        // sabit bir "PID    " dizesine göre bölmek kırılgan olurdu.
        let lines = out.stdout.split(separator: "\n", omittingEmptySubsequences: false)
        var bodyStart = 0
        for (index, line) in lines.enumerated()
        where line.hasPrefix("PID") && line.contains("CPU") {
            bodyStart = index + 1
        }
        let body = lines[bodyStart...]

        for line in body {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 4, let pid = Int32(fields[0]), pid > 0 else { continue }
            guard !seen.contains(pid) else { continue }

            let cpu = Double(fields[1]) ?? 0
            let power = Double(fields[2]) ?? 0
            let memory = parseMemory(fields[3])

            let app = apps[pid]
            let name = app?.localizedName ?? processName(for: pid) ?? "pid \(pid)"

            seen.insert(pid)
            rows.append(ProcessInfoRow(
                pid: pid,
                name: name,
                cpuPercent: cpu,
                energyImpact: power,
                memoryBytes: memory,
                isApp: app != nil,
                bundleIdentifier: app?.bundleIdentifier,
                // Yalnızca kullanıcının kendi GUI uygulamaları kapatılabilir —
                // sistem kabuğunu ayakta tutan süreçler hariç.
                canTerminate: app != nil
                    && app?.bundleIdentifier != Bundle.main.bundleIdentifier
                    && !ProtectedProcesses.contains(app?.bundleIdentifier)
            ))
        }

        return rows
    }

    /// Bellek tüketimine göre ilk N süreç.
    func sortedByMemory(_ rows: [ProcessInfoRow]) -> [ProcessInfoRow] {
        rows.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    // MARK: - Yardımcılar

    /// `271M`, `9648K`, `1.2G`, `512B` biçimlerini bayta çevirir. Sondaki +/- işaretini yok sayar.
    private func parseMemory(_ raw: String) -> UInt64 {
        var text = raw
        if let last = text.last, last == "+" || last == "-" { text.removeLast() }
        guard let unit = text.last else { return 0 }
        let numberPart = String(text.dropLast())
        guard let value = Double(numberPart) else { return UInt64(Double(text) ?? 0) }

        switch unit {
        case "K", "k": return UInt64(value * 1024)
        case "M", "m": return UInt64(value * 1024 * 1024)
        case "G", "g": return UInt64(value * 1024 * 1024 * 1024)
        case "T", "t": return UInt64(value * 1024 * 1024 * 1024 * 1024)
        case "B", "b": return UInt64(value)
        default: return UInt64(Double(text) ?? 0)
        }
    }

    /// `proc_pidpath` ile tam yürütülebilir yolunu alıp okunabilir bir isim üretir.
    private func processName(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer)
        guard !path.isEmpty else { return nil }

        // Yoldaki **ilk** .app paketini al: yardımcı süreçler
        // ".../Foo.app/Contents/Frameworks/.../2.1.220/Helper" gibi yollarda
        // sürüm klasörünü isim sanmayalım.
        if let appRange = path.range(of: ".app/") {
            let bundlePath = String(path[path.startIndex..<appRange.lowerBound]) + ".app"
            return URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
        }

        let basename = URL(fileURLWithPath: path).lastPathComponent
        // Bazı araçlar yürütülebilirlerini sürüm numarasıyla adlandırır
        // (ör. ~/.local/share/claude/versions/2.1.220). Böyle durumlarda
        // sürecin kendi argv[0]'ı çok daha okunabilir bir isim verir.
        if Self.looksLikeVersion(basename), let argv = argvZero(for: pid), !argv.isEmpty {
            return argv
        }
        return basename
    }

    private static func looksLikeVersion(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// `KERN_PROCARGS2` üzerinden sürecin argv[0] değeri.
    /// Başka kullanıcıların süreçlerinde başarısız olur; çağıran tarafta yedek isim vardır.
    private func argvZero(for pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // Yerleşim: [argc: Int32][exec yolu\0][dolgu \0...][argv[0]\0][argv[1]\0]...
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }     // exec yolunu atla
        while index < size, buffer[index] == 0 { index += 1 }     // dolguyu atla
        guard index < size else { return nil }

        let start = index
        while index < size, buffer[index] != 0 { index += 1 }
        guard index > start else { return nil }

        let bytes = buffer[start..<index].map { UInt8(bitPattern: $0) }
        let argument = String(decoding: bytes, as: UTF8.self)
        // argv[0] tam yol olabilir; son bileşeni yeterli.
        return argument.contains("/") ? URL(fileURLWithPath: argument).lastPathComponent : argument
    }
}

/// Kapatılması oturumu bozacak sistem süreçleri.
/// `loginwindow`'u kapatmak kullanıcıyı oturumdan atar; `Dock`/`Finder`
/// kapanınca masaüstü kullanılamaz hale gelir. Bunlara asla dokunmayız.
enum ProtectedProcesses {
    static let identifiers: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.Spotlight",
        "com.apple.TextInputMenuAgent",
        "com.apple.TextInputSwitcher",
        "com.apple.universalaccessAuthWarn",
        "com.apple.coreservices.uiagent",
        "com.apple.SecurityAgent",
        "com.apple.WebKit.GPU",
        "com.apple.keyboardservicesd",
    ]

    static func contains(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return identifiers.contains(identifier)
    }
}

/// GUI uygulamalarını **nazikçe** kapatma. Zorla öldürme yok, sinyal yok.
@MainActor
enum ProcessTerminator {

    enum Outcome: Sendable {
        case requested
        case notFound
        case notAllowed
    }

    static func requestQuit(pid: Int32) -> Outcome {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return .notAllowed }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return .notFound }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return .notAllowed }
        // İkinci savunma hattı: liste dışından bir çağrı gelse bile korunanlar geçmez.
        guard !ProtectedProcesses.contains(app.bundleIdentifier) else { return .notAllowed }

        // terminate() = Cmd+Q eşdeğeri: uygulama kaydedilmemiş veriyi sorabilir.
        return app.terminate() ? .requested : .notAllowed
    }
}
