import Foundation

/// **Aegis Skoru** — pil, bellek, depolama, termal ve enerji ölçümlerini
/// tek bir 0–100 sayısına indirger. Her bileşen ayrı puanlanır ve
/// ağırlıklandırılır; böylece "neden düşük" sorusunun cevabı hep görünür.
struct ScoreBreakdown: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let symbol: String
    let score: Double        // 0...100
    let weight: Double       // toplam içindeki payı
    let detail: String
}

struct AegisScore: Equatable, Sendable {
    var total: Double = 0
    var components: [ScoreBreakdown] = []

    var grade: String {
        switch total {
        case 90...: return "Mükemmel"
        case 80..<90: return "Çok İyi"
        case 65..<80: return "İyi"
        case 50..<65: return "Dikkat"
        default: return "Kritik"
        }
    }

    var weakest: ScoreBreakdown? {
        components.min { $0.score < $1.score }
    }
}

struct ScoreService: Sendable {

    func evaluate(battery: BatterySnapshot,
                  memory: MemorySnapshot,
                  volumes: [VolumeInfo],
                  processes: [ProcessInfoRow],
                  thermalState: ProcessInfo.ThermalState) -> AegisScore {

        var components: [ScoreBreakdown] = []

        // 1) Pil sağlığı — %100'de tam puan, %70'te sıfır.
        if battery.isPresent {
            let raw = (battery.healthPercent - 70) / 30 * 100
            let cyclePenalty = min(20, Double(battery.cycleCount) / 1000 * 20)
            components.append(ScoreBreakdown(
                name: "Pil",
                symbol: "battery.100percent.bolt",
                score: clamp(raw - cyclePenalty),
                weight: 0.25,
                detail: "\(Format.percent(battery.healthPercent)) sağlık, \(battery.cycleCount) döngü"
            ))
        }

        // 2) Bellek baskısı — düşük baskı yüksek puan.
        // Takas cezası AYRICA eklenmez: `pressurePercent` hesabı swap ağırlığını
        // zaten içeriyor (MemoryService.pressure). İkinci kez düşmek çift sayımdı.
        components.append(ScoreBreakdown(
            name: "Bellek",
            symbol: "memorychip",
            score: clamp(100 - memory.pressurePercent),
            weight: 0.25,
            // Ayrıntı metinleri kasten kabalaştırıldı: her örneklemede değişen bir
            // dize, skoru "değişti" gösterip kartı boşuna yeniden çizdiriyordu.
            detail: "\(Format.percent(memory.pressurePercent)) baskı, \(Format.bytesCompact(quantize(memory.swapUsedBytes, to: 100_000_000))) takas"
        ))

        // 3) Depolama — %70 doluluğa kadar tam puan, %95'te sıfır.
        if let disk = volumes.first(where: { $0.isInternal }) ?? volumes.first {
            let used = disk.usedFraction
            let raw = used <= 0.70 ? 100 : (0.95 - used) / 0.25 * 100
            components.append(ScoreBreakdown(
                name: "Depolama",
                symbol: "internaldrive",
                score: clamp(raw),
                weight: 0.20,
                detail: "\(Format.percent(used * 100)) dolu, \(Format.bytesCompact(quantize(disk.availableForImportantBytes, to: 500_000_000))) boş"
            ))
        }

        // 4) Enerji — en yüksek tekil tüketim + toplam yük.
        let totalEnergy = processes.reduce(0) { $0 + $1.energyImpact }
        let worst = processes.map(\.energyImpact).max() ?? 0
        components.append(ScoreBreakdown(
            name: "Enerji",
            symbol: "bolt.horizontal",
            score: clamp(100 - min(60, worst) - min(40, totalEnergy / 8)),
            weight: 0.18,
            detail: processes.isEmpty ? "ölçülüyor" : "toplam etki ~\(Int((totalEnergy / 10).rounded()) * 10)"
        ))

        // 5) Termal. Enum üzerinden eşlenir — görünen metne bağlanmak,
        //    metin değişirse skoru sessizce bozardı.
        let thermalScore: Double
        let thermalLabel: String
        switch thermalState {
        case .nominal: thermalScore = 100; thermalLabel = "Normal"
        case .fair: thermalScore = 78; thermalLabel = "Ilık"
        case .serious: thermalScore = 45; thermalLabel = "Sıcak"
        case .critical: thermalScore = 10; thermalLabel = "Kritik"
        @unknown default: thermalScore = 80; thermalLabel = "Bilinmiyor"
        }
        components.append(ScoreBreakdown(
            name: "Termal",
            symbol: "thermometer.medium",
            score: thermalScore,
            weight: 0.12,
            detail: thermalLabel
        ))

        let weightSum = components.reduce(0) { $0 + $1.weight }
        let total = weightSum > 0
            ? components.reduce(0) { $0 + $1.score * $1.weight } / weightSum
            : 0

        // Tam sayıya yuvarla: ekranda zaten tam sayı gösteriyoruz ve
        // ondalık gürültü her örneklemede kartı boşuna yeniden çizdiriyor.
        let rounded = components.map {
            ScoreBreakdown(name: $0.name, symbol: $0.symbol,
                           score: $0.score.rounded(), weight: $0.weight, detail: $0.detail)
        }
        return AegisScore(total: total.rounded(), components: rounded)
    }

    private func clamp(_ value: Double) -> Double { min(100, max(0, value)) }

    /// Değeri verilen adıma yuvarlar; gereksiz güncelleme gürültüsünü keser.
    private func quantize(_ value: UInt64, to step: UInt64) -> UInt64 {
        guard step > 0 else { return value }
        return (value / step) * step
    }
}
