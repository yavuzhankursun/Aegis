import Foundation

// MARK: - Battery

struct BatterySnapshot: Equatable, Sendable {
    var isPresent: Bool = false
    var chargePercent: Double = 0          // 0...100 (gerçek şarj yüzdesi)
    var cycleCount: Int = 0
    var designCapacity: Int = 0            // mAh
    var currentMaxCapacity: Int = 0        // mAh (NominalChargeCapacity)
    var rawMaxCapacity: Int = 0            // mAh (AppleRawMaxCapacity)
    var healthPercent: Double = 0          // 0...100
    var temperatureC: Double = 0
    var voltage: Double = 0                // V
    var amperage: Double = 0               // A (+ şarj, - deşarj)
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var minutesRemaining: Int = -1         // -1 = hesaplanıyor
    var condition: String = "—"
    var serial: String = "—"
    var permanentFailure: Bool = false
    var manufactureDate: Date?
    var lowPowerMode: Bool = false
    var chargeLimitEnabled: Bool = false

    var healthGrade: HealthGrade {
        if permanentFailure { return .critical }
        if healthPercent >= 90 { return .excellent }
        if healthPercent >= 80 { return .good }
        if healthPercent >= 70 { return .fair }
        return .critical
    }

    var wattage: Double { abs(voltage * amperage) }

    /// Apple tipik olarak 1000 döngüde %80 kapasite hedefler.
    var cycleLifePercent: Double { min(1.0, Double(cycleCount) / 1000.0) }
}

enum HealthGrade: String, Sendable {
    case excellent = "Mükemmel"
    case good = "İyi"
    case fair = "Orta"
    case critical = "Kritik"
}

// MARK: - Hardware

struct HardwareInfo: Equatable, Sendable {
    var marketingName: String = "Mac"
    var modelIdentifier: String = "—"
    var chipName: String = "—"
    var totalCores: Int = 0
    var performanceCores: Int = 0
    var efficiencyCores: Int = 0
    var gpuCores: Int = 0
    var memoryBytes: UInt64 = 0
    var memoryType: String = "—"
    var osName: String = "macOS"
    var osVersion: String = "—"
    var osBuild: String = "—"
    var kernel: String = "—"
    var serialNumber: String = "—"
    var uptime: TimeInterval = 0
    var architecture: String = "—"
    var secureBoot: String = "—"
    var sipEnabled: Bool? = nil
    var displays: [DisplayInfo] = []
    var thermalState: String = "Normal"
}

struct DisplayInfo: Equatable, Identifiable, Sendable {
    var id: String { name + "\(pixelWidth)x\(pixelHeight)" }
    var name: String
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshHz: Double
    var scale: Double
    var isMain: Bool
}

// MARK: - Memory

struct MemorySnapshot: Equatable, Sendable {
    var totalBytes: UInt64 = 0
    /// Gerçekten boş sayfalar (`free_count - speculative_count`).
    var freeBytes: UInt64 = 0
    var activeBytes: UInt64 = 0
    var inactiveBytes: UInt64 = 0
    var wiredBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0
    var speculativeBytes: UInt64 = 0
    var purgeableBytes: UInt64 = 0
    /// Dosya destekli sayfalar + boşaltılabilir sayfalar.
    var cachedFilesBytes: UInt64 = 0
    /// Anonim (dosya destekli olmayan) sayfalar eksi boşaltılabilirler.
    /// Activity Monitor'ün "Uygulama Belleği" satırının karşılığı.
    var appMemoryBytes: UInt64 = 0
    var swapUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
    var pressurePercent: Double = 0        // 0...100
    var pageIns: UInt64 = 0
    var pageOuts: UInt64 = 0

    /// Activity Monitor'ün "Kullanılan Bellek" tanımı:
    /// uygulama belleği + sabitlenmiş (wired) + sıkıştırılmış.
    /// Dosya önbelleği ve önokuma (speculative) sayfaları buraya dahil DEĞİLDİR —
    /// sistem baskı altında onları anında geri alabilir.
    var usedBytes: UInt64 { appMemoryBytes &+ wiredBytes &+ compressedBytes }
    var availableBytes: UInt64 { totalBytes > usedBytes ? totalBytes - usedBytes : 0 }

    var pressureLevel: PressureLevel {
        if pressurePercent >= 75 { return .critical }
        if pressurePercent >= 45 { return .warning }
        return .normal
    }
}

enum PressureLevel: String, Sendable {
    case normal = "Normal"
    case warning = "Uyarı"
    case critical = "Kritik"
}

// MARK: - CPU

struct CPUSnapshot: Equatable, Sendable {
    var userPercent: Double = 0
    var systemPercent: Double = 0
    var idlePercent: Double = 100
    var loadAvg1: Double = 0
    var loadAvg5: Double = 0
    var loadAvg15: Double = 0
    var processCount: Int = 0
    var threadCount: Int = 0
    var usedPercent: Double { min(100, max(0, userPercent + systemPercent)) }
}

// MARK: - Processes

struct ProcessInfoRow: Equatable, Identifiable, Sendable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var energyImpact: Double
    var memoryBytes: UInt64
    var isApp: Bool
    var bundleIdentifier: String?
    var canTerminate: Bool

    var energyBand: EnergyBand {
        if energyImpact >= 50 { return .severe }
        if energyImpact >= 20 { return .high }
        if energyImpact >= 5 { return .moderate }
        return .low
    }
}

enum EnergyBand: String, Sendable {
    case low = "Düşük"
    case moderate = "Orta"
    case high = "Yüksek"
    case severe = "Aşırı"
}

// MARK: - Storage

struct VolumeInfo: Equatable, Identifiable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var totalBytes: UInt64
    var freeBytes: UInt64
    var availableForImportantBytes: UInt64
    var isInternal: Bool
    var isRemovable: Bool
    var fileSystem: String
    var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }
    var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

struct StorageCategory: Equatable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var bytes: UInt64
    var symbol: String
}

// MARK: - Cleanup

enum CleanupRisk: String, Sendable {
    case safe = "Güvenli"
    case review = "Gözden Geçir"
}

struct CleanupTarget: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let risk: CleanupRisk
    /// Silinecek adaylar (dosya ya da klasör). Boş ise temiz.
    var items: [CleanupItem]
    var totalBytes: UInt64 { items.reduce(0) { $0 &+ $1.bytes } }
}

struct CleanupItem: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let bytes: UInt64
    let displayName: String
    let modified: Date?
}

struct CleanupResult: Sendable {
    var trashedCount: Int = 0
    var freedBytes: UInt64 = 0
    var failures: [String] = []
}
