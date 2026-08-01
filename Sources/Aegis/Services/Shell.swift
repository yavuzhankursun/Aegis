import Foundation

/// Sistem araçlarını **shell olmadan** çalıştıran ince katman.
///
/// Güvenlik notları:
/// - `/bin/sh -c` kullanılmaz → komut enjeksiyonu imkânsız.
/// - Sadece `allowedBinaries` içindeki mutlak yollar çalıştırılabilir.
/// - Her çağrının zaman aşımı vardır; asılı kalan süreç öldürülür.
/// - Yazma/silme yapan hiçbir sistem aracı listede yoktur (rm, diskutil vb. yok).
enum Shell {

    /// Uygulamanın çalıştırmasına izin verilen tek liste. Beyaz liste dışı hiçbir şey çalışmaz.
    static let allowedBinaries: Set<String> = [
        "/usr/bin/top",
        "/usr/sbin/system_profiler",
        "/usr/bin/vm_stat",
        "/usr/bin/sysctl",
        "/usr/bin/uptime",
        "/usr/bin/pmset",
        "/usr/sbin/sysctl",
        "/usr/bin/csrutil",
        "/usr/bin/du",
        "/usr/sbin/ioreg",
    ]

    struct Output: Sendable {
        var stdout: String
        var status: Int32
        var timedOut: Bool
    }

    /// Bloklayan işler için ayrılmış havuz.
    ///
    /// `Shell.run` alt sürecin bitmesini beklerken thread'i bloklar. Bu bekleyiş
    /// Swift eşzamanlılığının **cooperative** havuzunda olursa (çekirdek sayısı kadar
    /// thread vardır) havuz tükenir ve ilgisiz `await`'ler saniyelerce donar.
    /// Bu yüzden bloklayan her çağrı buraya taşınır.
    private static let blockingQueue = DispatchQueue(
        label: "aegis.blocking",
        qos: .utility,
        attributes: .concurrent
    )

    /// Bloklayan bir işi cooperative havuzun dışında çalıştırır.
    static func offloaded<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            blockingQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 8) -> Output {
        guard allowedBinaries.contains(path), FileManager.default.isExecutableFile(atPath: path) else {
            return Output(stdout: "", status: -1, timedOut: false)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return Output(stdout: "", status: -1, timedOut: false)
        }

        // Pipe'ı ana thread'i bloklamadan boşalt; aksi halde 64KB buffer dolunca deadlock olur.
        let collector = DataCollector()
        let handle = pipe.fileHandleForReading
        let readQueue = DispatchQueue(label: "aegis.shell.read")
        readQueue.async {
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                collector.append(chunk)
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                usleep(200_000)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                timedOut = true
                break
            }
            usleep(20_000)
        }
        process.waitUntilExit()
        readQueue.sync { }   // okuma bitene kadar bekle

        let text = String(data: collector.data, encoding: .utf8) ?? ""
        return Output(stdout: text, status: process.terminationStatus, timedOut: timedOut)
    }

    /// JSON döndüren system_profiler çağrıları için yardımcı.
    static func systemProfilerJSON(_ dataType: String, timeout: TimeInterval = 10) -> [String: Any]? {
        let out = run("/usr/sbin/system_profiler", ["-json", dataType], timeout: timeout)
        guard !out.stdout.isEmpty, let data = out.stdout.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// Thread-safe byte biriktirici.
private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock(); storage.append(chunk); lock.unlock()
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
