import Foundation
import IOKit

/// Pil gauge yongasının (bq40z…) ömür boyu tuttuğu ham kayıt.
/// Bu veriler Activity Monitor'da, Sistem Bilgisi'nde ya da piyasadaki
/// çoğu pil aracında **görünmez**; doğrudan AppleSmartBattery → BatteryData
/// düğümünden okunur.
struct BatteryLifetime: Equatable, Sendable {
    var totalOperatingHours: Int = 0
    var cycleCountLastQmax: Int = 0
    var minimumTemperatureC: Int = 0
    var maximumTemperatureC: Int = 0
    var averageTemperatureC: Double = 0
    var maximumChargeCurrentmA: Int = 0
    var maximumDischargeCurrentmA: Int = 0
    var minimumPackVoltagemV: Int = 0
    var maximumPackVoltagemV: Int = 0
    var dailyMaxSoc: Int = 0
    var dailyMinSoc: Int = 0
    var cellVoltagesmV: [Int] = []
    var qmaxPerCell: [Int] = []
    var chemistryID: Int = 0
    var flashWriteCount: Int = 0
    var isAvailable: Bool = false

    /// Hücreler arası en büyük gerilim farkı. 50 mV üstü dengesizlik işaretidir.
    var cellImbalancemV: Int {
        guard let high = cellVoltagesmV.max(), let low = cellVoltagesmV.min() else { return 0 }
        return high - low
    }

    var balanceVerdict: (text: String, healthy: Bool) {
        switch cellImbalancemV {
        case ..<20: return ("Hücreler dengeli", true)
        case ..<50: return ("Hafif dengesizlik", true)
        default: return ("Dengesiz — servis kontrolü", false)
        }
    }
}

/// Pil aşınma tahmini.
struct BatteryForecast: Equatable, Sendable {
    var wearPerCycle: Double = 0          // her döngüde kaybedilen % kapasite
    var cyclesTo80Percent: Int = -1
    var cyclesToDesignLimit: Int = -1
    var cyclesPerDay: Double = 0
    var daysTo80Percent: Int = -1
    var estimatedDate: Date?
    var isReliable: Bool = false          // yeterli veri var mı

    /// Kayıp, gauge'ın kalibrasyon gürültüsü bandının (< %1) içinde —
    /// "hız" diye bölünecek gerçek bir sinyal yok.
    var wearIsNegligible = false
    /// Ölçülen hız gerçek ama eşik 10 yıldan uzak: bu ufukta döngü aşınması
    /// değil takvim yaşlanması belirleyicidir, tarih vermek sahte kesinliktir.
    var horizonExceeded = false

    var summary: String {
        if wearIsNegligible {
            return "Kapasite kaybı henüz ölçüm güvenilirliği bandının altında (%1'den az). "
                 + "Gauge'ın tam-kapasite değeri yeniden kalibrasyonlar arasında zaten bu kadar "
                 + "oynar; gürültüden on yıllara uzanan tarih türetmek yanıltıcı olur. "
                 + "Kayıp %1'i aşınca tahmin burada görünecek."
        }
        if cyclesTo80Percent == 0 {
            return "Kapasite %80 eşiğinin altında ya da eşikte. Apple bu noktada pil servisini "
                 + "değerlendirmeyi önerir; tahmin edilecek kalan mesafe yok."
        }
        if horizonExceeded {
            return "Ölçülen döngü aşınması bu tempoyla %80 eşiğine 10 yıldan uzak bir tarihe "
                 + "işaret ediyor. O ölçekte pil ömrünü döngü değil takvim yaşlanması belirler — "
                 + "doğrusal modelin geçerli olduğu aralığın dışındayız, tarih verilmez."
        }
        guard isReliable, daysTo80Percent > 0 else {
            return "Tahmin için yeterli döngü verisi yok. Pil biraz daha kullanıldıkça netleşecek."
        }
        let months = daysTo80Percent / 30
        if months >= 24 { return "Bu tempoyla %80 eşiğine ~\(months / 12) yıl \(months % 12) ay var." }
        if months >= 1 { return "Bu tempoyla %80 eşiğine ~\(months) ay var." }
        return "Bu tempoyla %80 eşiğine ~\(daysTo80Percent) gün var."
    }
}

struct BatteryLifetimeService: Sendable {

    func read() -> BatteryLifetime {
        var result = BatteryLifetime()

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return result }
        defer { IOObjectRelease(service) }

        guard let raw = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else { return result }

        result.isAvailable = true
        result.dailyMaxSoc = int(raw["DailyMaxSoc"])
        result.dailyMinSoc = int(raw["DailyMinSoc"])
        result.chemistryID = int(raw["ChemID"])
        result.flashWriteCount = int(raw["DataFlashWriteCount"])
        result.cellVoltagesmV = intArray(raw["CellVoltage"])
        result.qmaxPerCell = intArray(raw["Qmax"])

        if let lifetime = raw["LifetimeData"] as? [String: Any] {
            result.totalOperatingHours = int(lifetime["TotalOperatingTime"])
            result.cycleCountLastQmax = int(lifetime["CycleCountLastQmax"])
            result.minimumTemperatureC = int(lifetime["MinimumTemperature"])
            result.maximumTemperatureC = int(lifetime["MaximumTemperature"])
            // Ortalama sıcaklık 0.1 °C çözünürlükte tutulur.
            result.averageTemperatureC = Double(int(lifetime["AverageTemperature"])) / 10.0
            result.maximumChargeCurrentmA = int(lifetime["MaximumChargeCurrent"])
            result.maximumDischargeCurrentmA = signed(lifetime["MaximumDischargeCurrent"])
            result.minimumPackVoltagemV = int(lifetime["MinimumPackVoltage"])
            result.maximumPackVoltagemV = int(lifetime["MaximumPackVoltage"])
        }

        return result
    }

    /// Kaybın "gerçek sinyal" sayılması için alt sınır (yüzde puanı).
    /// NominalChargeCapacity yeniden kalibrasyonlar arasında ~±%1 oynar;
    /// bandın içindeki kayıptan hız türetmek gürültüyü yıla çevirmektir.
    private static let measurableLossFloor = 1.0

    /// Doğrusal döngü modelinin anlamlı kaldığı en uzak ufuk (~10 yıl).
    /// Ötesinde takvim yaşlanması baskındır; tarih üretilmez.
    private static let forecastHorizonDays = 3650

    /// Mevcut aşınma hızından %80 eşiğine kalan süreyi tahmin eder.
    func forecast(battery: BatterySnapshot, lifetime: BatteryLifetime) -> BatteryForecast {
        var forecast = BatteryForecast()
        guard battery.isPresent, battery.cycleCount > 0, battery.healthPercent > 0 else { return forecast }

        forecast.cyclesToDesignLimit = max(0, 1000 - battery.cycleCount)

        // Günlük döngü hızı: gauge'ın raporladığı toplam çalışma saatinden türetilir.
        let operatingDays = Double(lifetime.totalOperatingHours) / 24.0
        if operatingDays >= 7 {
            forecast.cyclesPerDay = Double(battery.cycleCount) / operatingDays
        }

        if battery.healthPercent <= 80 {
            forecast.cyclesTo80Percent = 0
            return forecast
        }

        // Ölçüm güveni kapısı: kayıp gürültü bandının içindeyse tahmin YOK.
        let lost = max(0, 100 - battery.healthPercent)
        forecast.wearIsNegligible = lost < Self.measurableLossFloor
        guard !forecast.wearIsNegligible else { return forecast }

        forecast.wearPerCycle = lost / Double(battery.cycleCount)
        forecast.cyclesTo80Percent = Int((battery.healthPercent - 80) / forecast.wearPerCycle)

        if forecast.cyclesPerDay > 0.01, forecast.cyclesTo80Percent > 0 {
            // 25 döngüden az veriyle yapılan tahmin gürültülüdür.
            forecast.isReliable = battery.cycleCount >= 25
            let days = Int(Double(forecast.cyclesTo80Percent) / forecast.cyclesPerDay)
            if days > Self.forecastHorizonDays {
                // Ufuk kapısı: "13 Eyl 2086" gibi bir tarih matematiksel olarak
                // türetilebilir ama fiziksel olarak anlamsızdır — söylemeyiz.
                forecast.horizonExceeded = true
            } else {
                forecast.daysTo80Percent = days
                forecast.estimatedDate = Calendar.current.date(byAdding: .day, value: days, to: Date())
            }
        }

        return forecast
    }

    // MARK: - Dönüşüm

    private func int(_ any: Any?) -> Int {
        if let n = any as? NSNumber { return n.intValue }
        if let n = any as? Int { return n }
        return 0
    }

    private func signed(_ any: Any?) -> Int {
        guard let n = any as? NSNumber else { return 0 }
        let raw = n.uint64Value
        if raw > UInt64(Int64.max) { return Int(Int64(bitPattern: raw)) }
        return n.intValue
    }

    private func intArray(_ any: Any?) -> [Int] {
        guard let array = any as? [Any] else { return [] }
        return array.compactMap { ($0 as? NSNumber)?.intValue }.filter { $0 > 0 }
    }
}
