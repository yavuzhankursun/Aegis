import Foundation
import AppKit
import IOKit

/// Donanım künyesi. Pahalı kısımlar (system_profiler) yalnızca bir kez okunur.
struct HardwareService: Sendable {

    func snapshot(cached: HardwareInfo? = nil) -> HardwareInfo {
        var info = cached ?? staticInfo()

        // Sadece bunlar canlı güncellenir.
        info.uptime = SysctlKit.bootTime.map { Date().timeIntervalSince($0) } ?? 0
        info.thermalState = thermalStateText()
        info.displays = displays()
        return info
    }

    /// Değişmeyen alanlar — uygulama açılışında bir defa.
    func staticInfo() -> HardwareInfo {
        var info = HardwareInfo()

        info.modelIdentifier = SysctlKit.string("hw.model") ?? "—"
        info.chipName = SysctlKit.string("machdep.cpu.brand_string") ?? "—"
        info.totalCores = SysctlKit.int("hw.ncpu") ?? 0
        info.performanceCores = SysctlKit.int("hw.perflevel0.logicalcpu") ?? 0
        info.efficiencyCores = SysctlKit.int("hw.perflevel1.logicalcpu") ?? 0
        info.memoryBytes = SysctlKit.uint64("hw.memsize") ?? 0
        info.kernel = SysctlKit.string("kern.version")?
            .components(separatedBy: ":").first?
            .trimmingCharacters(in: .whitespaces) ?? "—"

        #if arch(arm64)
        info.architecture = "Apple Silicon (arm64)"
        #else
        info.architecture = "Intel (x86_64)"
        #endif

        let os = ProcessInfo.processInfo.operatingSystemVersion
        info.osVersion = "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
        info.osName = macOSName(major: os.majorVersion)
        info.osBuild = SysctlKit.string("kern.osversion") ?? "—"

        if let hw = Shell.systemProfilerJSON("SPHardwareDataType")?["SPHardwareDataType"] as? [[String: Any]],
           let first = hw.first {
            info.marketingName = (first["machine_name"] as? String) ?? info.modelIdentifier
            info.serialNumber = Snapshot.privacyMasked
                ? Snapshot.maskText
                : (first["serial_number"] as? String) ?? "—"
            info.memoryType = (first["physical_memory"] as? String) ?? Format.bytes(info.memoryBytes)
            if let chip = first["chip_type"] as? String { info.chipName = chip }
        } else {
            info.marketingName = info.modelIdentifier
            info.memoryType = Format.bytes(info.memoryBytes)
        }

        info.gpuCores = gpuCoreCount()
        info.sipEnabled = sipStatus()
        return info
    }

    // MARK: - Parçalar

    private func gpuCoreCount() -> Int {
        let matching = IOServiceMatching("AGXAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let value = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber {
                return value.intValue
            }
        }
        return 0
    }

    private func sipStatus() -> Bool? {
        let out = Shell.run("/usr/bin/csrutil", ["status"], timeout: 4)
        guard !out.stdout.isEmpty else { return nil }
        let text = out.stdout.lowercased()
        if text.contains("enabled") { return true }
        if text.contains("disabled") { return false }
        return nil
    }

    private func thermalStateText() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Ilık"
        case .serious: return "Sıcak"
        case .critical: return "Kritik"
        @unknown default: return "Bilinmiyor"
        }
    }

    @MainActor
    private func mainActorDisplays() -> [DisplayInfo] { displaysFromScreens() }

    private func displays() -> [DisplayInfo] {
        if Thread.isMainThread { return displaysFromScreens() }
        return DispatchQueue.main.sync { displaysFromScreens() }
    }

    private func displaysFromScreens() -> [DisplayInfo] {
        NSScreen.screens.map { screen in
            let frame = screen.frame
            let scale = screen.backingScaleFactor
            return DisplayInfo(
                name: screen.localizedName,
                pixelWidth: Int(frame.width * scale),
                pixelHeight: Int(frame.height * scale),
                refreshHz: screen.maximumFramesPerSecond > 0 ? Double(screen.maximumFramesPerSecond) : 60,
                scale: scale,
                isMain: screen == NSScreen.main
            )
        }
    }

    private func macOSName(major: Int) -> String {
        switch major {
        case 26: return "macOS Tahoe"
        case 15: return "macOS Sequoia"
        case 14: return "macOS Sonoma"
        case 13: return "macOS Ventura"
        case 12: return "macOS Monterey"
        default: return "macOS"
        }
    }
}
