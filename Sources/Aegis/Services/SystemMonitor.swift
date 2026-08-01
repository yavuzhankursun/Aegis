import SwiftUI
import AppKit
import Observation

/// Uygulamanın tek veri kaynağı.
///
/// Kendi kaynak tüketimini kontrol altında tutar:
/// - Pencere gizli/örtülü olduğunda **tüm örnekleme durur**.
/// - Pahalı işler (süreç listesi, disk taraması) yalnızca ilgili sekme açıkken çalışır.
/// - Her örnekleme arka plan thread'inde yapılır; ana thread yalnızca yazma yapar.
@MainActor
@Observable
final class SystemMonitor {

    // MARK: - Yayınlanan durum

    var battery = BatterySnapshot()
    var memory = MemorySnapshot()
    var cpu = CPUSnapshot()
    var hardware = HardwareInfo()
    var volumes: [VolumeInfo] = []
    var processes: [ProcessInfoRow] = []
    var storageCategories: [StorageCategory] = []
    var score = AegisScore()
    var batteryLifetime = BatteryLifetime()
    var batteryForecast = BatteryForecast()
    var startupItems: [StartupItem] = []

    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var batteryHistory: [Double] = []

    var isSampling = false
    var isLoadingProcesses = false
    var isScanningStorage = false
    var lastUpdate: Date?

    /// Aktif sekme — pahalı örneklemeleri buna göre açıp kapatırız.
    var activeSection: Section = .dashboard {
        didSet { Task { await refreshForSection() } }
    }

    enum Section: String, CaseIterable, Identifiable, Sendable {
        case dashboard = "Genel Bakış"
        case battery = "Pil"
        case performance = "Performans"
        case energy = "Enerji"
        case storage = "Depolama"
        case cleanup = "Temizlik"
        case startup = "Başlangıç"
        case hardware = "Donanım"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .dashboard: return "square.grid.2x2"
            case .battery: return "battery.100percent.bolt"
            case .performance: return "gauge.with.dots.needle.67percent"
            case .energy: return "bolt.horizontal"
            case .storage: return "internaldrive"
            case .cleanup: return "sparkles"
            case .startup: return "power"
            case .hardware: return "cpu"
            }
        }

        var accent: Color {
            switch self {
            // Sekiz sekmenin sekizi de ayrı renk: iki sekme aynı vurguyu paylaşırsa
            // kenar çubuğundaki seçim göstergesi bilgi taşımaz.
            case .dashboard: return Theme.cyan
            case .battery: return Theme.teal
            case .performance: return Theme.steel
            case .energy: return Theme.amber
            case .storage: return Theme.plasma
            case .cleanup: return Theme.orange
            case .startup: return Theme.lime
            case .hardware: return Theme.titanium
            }
        }
    }

    // MARK: - Servisler

    private let batteryService = BatteryService()
    private let memoryService = MemoryService()
    private let cpuService = CPUService()
    private let hardwareService = HardwareService()
    private let storageService = StorageService()
    private let processService = ProcessService()
    private let scoreService = ScoreService()
    private let lifetimeService = BatteryLifetimeService()
    private let startupService = StartupService()

    private var loopTask: Task<Void, Never>?
    private var processTask: Task<Void, Never>?
    private var storageTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var didBootstrapHardware = false
    private var tickCount = 0
    /// `stop()` her çağrıldığında artar; uçuştaki görevler dönerken kendi
    /// nesillerinin hâlâ geçerli olup olmadığını kontrol eder.
    private var generation: UInt64 = 0

    private let historyLimit = 90

    // MARK: - Yaşam döngüsü

    func start() {
        guard loopTask == nil else { return }
        isSampling = true

        // Donanım künyesi `system_profiler` + `csrutil` çalıştırır: pahalı ve
        // değişmez. Uygulama ömrü boyunca bir kez, takip edilen bir görevde.
        if bootstrapTask == nil, !didBootstrapHardware {
            bootstrapTask = Task { [weak self] in
                guard let self else { return }
                let info = await Shell.offloaded { [hardwareService] in
                    hardwareService.staticInfo()
                }
                guard !Task.isCancelled else { self.bootstrapTask = nil; return }
                self.hardware = self.hardwareService.snapshot(cached: info)
                self.didBootstrapHardware = true
                self.bootstrapTask = nil
            }
        }

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let interval = self.currentInterval()
                try? await Task.sleep(for: .seconds(interval))
            }
        }

        refreshVolumes()
    }

    func stop() {
        loopTask?.cancel(); loopTask = nil
        bootstrapTask?.cancel(); bootstrapTask = nil
        processTask?.cancel(); processTask = nil
        storageTask?.cancel(); storageTask = nil
        // Nesil sayacını ilerlet: uçuşta olan görevlerin geç dönen sonuçları
        // yeni bir turun durumunu ezmesin.
        generation &+= 1
        isLoadingProcesses = false
        isScanningStorage = false
        isSampling = false
    }

    /// Pencere örtüldüğünde çağrılır — CPU tüketimini sıfıra indirir.
    func setActive(_ active: Bool) {
        if active {
            start()
        } else {
            stop()
        }
    }

    // MARK: - Örnekleme

    private func currentInterval() -> Double {
        switch activeSection {
        case .performance: return 2.0
        case .dashboard: return 3.0
        case .energy: return 4.0
        case .battery: return 5.0
        default: return 10.0
        }
    }

    private func tick() async {
        tickCount += 1

        // Pil ve donanım yavaş değişir; her turda örneklemek boşuna yeniden çizim demek.
        let wantsBattery = tickCount % 3 == 1
        let wantsHardware = tickCount % 10 == 1

        let sampled = await Task.detached(priority: .utility) { [memoryService, cpuService, batteryService] in
            (memory: memoryService.snapshot(),
             cpu: cpuService.snapshot(),
             battery: wantsBattery ? batteryService.snapshot() : nil)
        }.value

        // Doğrudan karşılaştırıp yazıyoruz. `inout` ile geçmek Observation'ın
        // `_modify` erişimcisini tetikler ve değer aynı olsa bile "değişti"
        // bildirimi yayar; o yüzden setter'a yalnızca gerçekten farklıysa gidilir.
        if memory != sampled.memory { memory = sampled.memory }
        if cpu != sampled.cpu { cpu = sampled.cpu }
        if let newBattery = sampled.battery {
            if battery != newBattery { battery = newBattery }
            append(&batteryHistory, newBattery.chargePercent)
            refreshBatteryLifetime()
        }
        if wantsHardware {
            let refreshed = hardwareService.snapshot(cached: hardware)
            if hardware != refreshed { hardware = refreshed }
        }
        lastUpdate = Date()

        append(&cpuHistory, sampled.cpu.usedPercent)
        append(&memoryHistory, sampled.memory.pressurePercent)

        // Enerji sekmesi açıkken süreç listesini tazele (~her 3 tick).
        if (activeSection == .energy || activeSection == .performance || activeSection == .dashboard),
           tickCount % 4 == 2 {
            refreshProcesses()
        }

        // Disk doluluk oranı yavaş değişir.
        if tickCount % 15 == 1 { refreshVolumes() }

        recomputeScore()
    }

    private func append(_ buffer: inout [Double], _ value: Double) {
        buffer.append(value)
        if buffer.count > historyLimit { buffer.removeFirst(buffer.count - historyLimit) }
    }

    // MARK: - İsteğe bağlı yenilemeler

    func refreshProcesses() {
        guard processTask == nil else { return }
        isLoadingProcesses = processes.isEmpty
        let epoch = generation

        processTask = Task { [weak self] in
            guard let self else { return }
            // `top` alt süreç bitene kadar bloklar — cooperative havuzun dışında.
            let rows = await Shell.offloaded { [processService] in
                processService.topProcesses()
            }
            // Bu arada stop() çağrıldıysa sonucu yut: yeni turun durumunu ezmemeli.
            guard !Task.isCancelled, epoch == self.generation else { return }
            if !rows.isEmpty, rows != self.processes { self.processes = rows }
            self.isLoadingProcesses = false
            self.processTask = nil
        }
    }

    func refreshVolumes() {
        let epoch = generation
        Task { [weak self] in
            guard let self else { return }
            let list = await Shell.offloaded { [storageService] in
                storageService.volumes()
            }
            guard !Task.isCancelled, epoch == self.generation else { return }
            if list != self.volumes { self.volumes = list }
        }
    }

    func scanStorageCategories() {
        guard storageTask == nil else { return }
        isScanningStorage = true
        let epoch = generation

        storageTask = Task { [weak self] in
            guard let self else { return }
            let categories = await Shell.offloaded { [storageService] in
                storageService.homeCategories()
            }
            guard !Task.isCancelled, epoch == self.generation else { return }
            if categories != self.storageCategories { self.storageCategories = categories }
            self.isScanningStorage = false
            self.storageTask = nil
        }
    }

    private func refreshForSection() async {
        switch activeSection {
        case .energy, .performance:
            refreshProcesses()
        case .storage:
            refreshVolumes()
            if storageCategories.isEmpty { scanStorageCategories() }
        case .battery:
            refreshBatteryLifetime()
        case .startup:
            refreshStartupItems()
        default:
            break
        }
    }

    /// Aegis Skoru — her tikte yeniden hesaplanır, maliyeti ihmal edilebilir.
    private func recomputeScore() {
        let fresh = scoreService.evaluate(
            battery: battery, memory: memory, volumes: volumes,
            processes: processes, thermalState: ProcessInfo.processInfo.thermalState
        )
        if score != fresh { score = fresh }
    }

    func refreshBatteryLifetime() {
        Task { [weak self] in
            guard let self else { return }
            let data = await Shell.offloaded { [lifetimeService] in lifetimeService.read() }
            if self.batteryLifetime != data { self.batteryLifetime = data }
            let projection = self.lifetimeService.forecast(battery: self.battery, lifetime: data)
            if self.batteryForecast != projection { self.batteryForecast = projection }
        }
    }

    func refreshStartupItems() {
        guard startupItems.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let items = await Shell.offloaded { [startupService] in startupService.scan() }
            if items != self.startupItems { self.startupItems = items }
        }
    }

    // MARK: - Türetilmiş içgörüler

    var insights: [Insight] {
        var list: [Insight] = []

        if battery.isPresent {
            if battery.healthPercent > 0 && battery.healthPercent < 80 {
                list.append(Insight(
                    id: "pil-sagligi",
                severity: .warning,
                    symbol: "battery.25percent",
                    title: "Pil sağlığı düşük",
                    detail: "Tasarım kapasitesinin altına indi. Apple pil değişimini %80 eşiğinde önerir."
                ))
            }
            if battery.cycleCount > 800 {
                list.append(Insight(
                    id: "pil-dongusu",
                severity: .warning,
                    symbol: "arrow.triangle.2.circlepath",
                    title: "\(battery.cycleCount) şarj döngüsü",
                    detail: "Tasarım ömrü 1000 döngü. Pil ömrü sonuna yaklaşıyor."
                ))
            }
            if battery.temperatureC > 40 {
                list.append(Insight(
                    id: "pil-sicakligi",
                severity: .warning,
                    symbol: "thermometer.high",
                    title: "Pil sıcaklığı \(Format.temperature(battery.temperatureC))",
                    detail: "Uzun süreli yüksek sıcaklık pil sağlığını hızla düşürür."
                ))
            }
        }

        if memory.pressureLevel != .normal {
            list.append(Insight(
                id: "bellek-baskisi",
                severity: memory.pressureLevel == .critical ? .critical : .warning,
                symbol: "memorychip",
                title: "Bellek baskısı \(memory.pressureLevel.rawValue.lowercased())",
                detail: "Sistem sıkıştırma ve takas kullanıyor. Bellek tüketen uygulamaları kapatmayı düşün."
            ))
        }

        if memory.swapUsedBytes > 2_000_000_000 {
            list.append(Insight(
                id: "takas-alani",
                severity: .warning,
                symbol: "arrow.left.arrow.right.square",
                title: "Takas alanı \(Format.bytesCompact(memory.swapUsedBytes))",
                detail: "Disk üzerinde bellek kullanımı yüksek — sistem yavaşlayabilir."
            ))
        }

        for volume in volumes where volume.isInternal && volume.usedFraction > 0.90 {
            list.append(Insight(
                id: "disk-dolu",
                severity: .critical,
                symbol: "internaldrive.badge.xmark",
                title: "\(volume.name) neredeyse dolu",
                detail: "macOS'un düzgün çalışması için en az %10 boş alan bırak."
            ))
        }

        if let hungry = processes.filter({ $0.canTerminate }).max(by: { $0.energyImpact < $1.energyImpact }),
           hungry.energyImpact > 30 {
            list.append(Insight(
                id: "enerji-suclusu",
                severity: .warning,
                symbol: "bolt.trianglebadge.exclamationmark",
                title: "\(hungry.name) yüksek enerji tüketiyor",
                detail: "Enerji etkisi \(Int(hungry.energyImpact)). Pil ömrünü belirgin şekilde kısaltıyor."
            ))
        }

        if hardware.thermalState != "Normal" {
            list.append(Insight(
                id: "termal",
                severity: hardware.thermalState == "Kritik" ? .critical : .warning,
                symbol: "fan",
                title: "Termal durum: \(hardware.thermalState)",
                detail: "Sistem performansı düşürüyor olabilir. Ağır işleri duraklatmayı düşün."
            ))
        }

        // Skorun en zayıf halkası da bir uyarı olarak yüzeye çıkar.
        if let weak = score.weakest, weak.score < 60,
           !list.contains(where: { $0.title.localizedCaseInsensitiveContains(weak.name) }) {
            list.append(Insight(
                id: "skor-zayif",
                severity: weak.score < 40 ? .critical : .warning,
                symbol: weak.symbol,
                title: "\(weak.name) skoru \(Int(weak.score))/100",
                detail: "Aegis Skorunu en çok aşağı çeken bileşen bu: \(weak.detail)."
            ))
        }

        if list.isEmpty {
            list.append(Insight(
                id: "her-sey-yolunda",
                severity: .good,
                symbol: "checkmark.seal",
                title: "Her şey yolunda",
                detail: "Pil, bellek, depolama ve termal ölçümlerin tamamı sağlıklı aralıkta."
            ))
        }

        return list
    }
}

struct Insight: Identifiable, Sendable {
    enum Severity: Sendable {
        case good, warning, critical

        var color: Color {
            switch self {
            case .good: return Theme.mint
            case .warning: return Theme.amber
            case .critical: return Theme.coral
            }
        }
    }

    /// Kimlik SABİT bir tür anahtarıdır — başlıktan türetilemez, çünkü başlıkta
    /// canlı ölçüm var ("Takas alanı 2,1 GB"). Değişen bir kimlik SwiftUI'ya
    /// "satır silindi, yenisi eklendi" dedirtip her tikte listeyi baştan kurdurur.
    let id: String
    let severity: Severity
    let symbol: String
    let title: String
    let detail: String
}
