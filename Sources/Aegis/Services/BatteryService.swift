import Foundation
import IOKit
import IOKit.ps

/// AppleSmartBattery IORegistry düğümünü **salt okunur** olarak okur.
/// Hiçbir yazma / SMC müdahalesi yapmaz.
struct BatteryService: Sendable {

    func snapshot() -> BatterySnapshot {
        var snap = BatterySnapshot()
        snap.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let props = readRegistry() else {
            snap.isPresent = false
            return snap
        }

        snap.isPresent = (props["BatteryInstalled"] as? Bool) ?? true
        snap.cycleCount = intValue(props["CycleCount"]) ?? 0
        snap.designCapacity = intValue(props["DesignCapacity"]) ?? 0
        snap.currentMaxCapacity = intValue(props["NominalChargeCapacity"]) ?? 0
        snap.rawMaxCapacity = intValue(props["AppleRawMaxCapacity"]) ?? 0
        snap.isCharging = (props["IsCharging"] as? Bool) ?? false
        snap.isPluggedIn = (props["ExternalConnected"] as? Bool) ?? false
        snap.serial = (props["Serial"] as? String) ?? "—"
        snap.permanentFailure = (intValue(props["PermanentFailureStatus"]) ?? 0) != 0

        if let t = intValue(props["Temperature"]) { snap.temperatureC = Double(t) / 100.0 }
        if let v = intValue(props["Voltage"]) { snap.voltage = Double(v) / 1000.0 }
        snap.amperage = signedValue(props["Amperage"]).map { Double($0) / 1000.0 } ?? 0

        // Şarj yüzdesi: mAh oranı en doğrusu, yoksa CurrentCapacity yüzdesine düş.
        let rawCurrent = intValue(props["AppleRawCurrentCapacity"]) ?? 0
        if rawCurrent > 0, snap.rawMaxCapacity > 0 {
            snap.chargePercent = min(100, Double(rawCurrent) / Double(snap.rawMaxCapacity) * 100)
        } else if let cc = intValue(props["CurrentCapacity"]) {
            snap.chargePercent = Double(cc)
        }

        // Sağlık: mevcut tam dolu kapasite / tasarım kapasitesi.
        if snap.designCapacity > 0 {
            let maxCap = snap.currentMaxCapacity > 0 ? snap.currentMaxCapacity : snap.rawMaxCapacity
            snap.healthPercent = min(100, Double(maxCap) / Double(snap.designCapacity) * 100)
        }

        if let remaining = intValue(props["TimeRemaining"]), remaining > 0, remaining < 65535 {
            snap.minutesRemaining = remaining
        } else {
            snap.minutesRemaining = -1
        }

        snap.condition = powerSourceCondition() ?? (snap.permanentFailure ? "Servis Gerekli" : "Normal")
        return snap
    }

    // MARK: - IORegistry

    private func readRegistry() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    /// IOPowerSources üzerinden Apple'ın kendi "Condition" değerlendirmesi.
    private func powerSourceCondition() -> String? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            if let health = desc[kIOPSBatteryHealthKey as String] as? String {
                switch health {
                case "Good": return "Normal"
                case "Fair": return "Yakında Değişmeli"
                case "Poor": return "Servis Gerekli"
                default: return health
                }
            }
        }
        return nil
    }

    // MARK: - Sayı dönüşümü

    private func intValue(_ any: Any?) -> Int? {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    /// IORegistry akımı 64-bit işaretsiz olarak sarmalar; işaretli değere çevirir.
    private func signedValue(_ any: Any?) -> Int64? {
        guard let n = any as? NSNumber else { return nil }
        let raw = n.uint64Value
        if raw > UInt64(Int64.max) { return Int64(bitPattern: raw) }
        return Int64(raw)
    }
}
