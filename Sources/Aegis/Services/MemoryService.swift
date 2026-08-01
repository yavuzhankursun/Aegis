import Foundation
import Darwin

/// Mach `host_statistics64` üzerinden bellek telemetrisi.
struct MemoryService: Sendable {

    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size == 0 ? 16384 : size)
    }()

    func snapshot() -> MemorySnapshot {
        var snap = MemorySnapshot()
        snap.totalBytes = SysctlKit.uint64("hw.memsize") ?? 0

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return snap }

        func bytes(_ pages: UInt32) -> UInt64 { UInt64(pages) &* pageSize }
        func bytes64(_ pages: UInt64) -> UInt64 { pages &* pageSize }

        // XNU'da `free_count` önokuma (speculative) sayfalarını da içerir —
        // `vm_stat` aracının "Pages free" satırı da farkı alarak yazdırır.
        // Çıkarmazsak hem Boş hem Önbellek aynı sayfaları sayar.
        let trulyFree = stats.free_count > stats.speculative_count
            ? stats.free_count - stats.speculative_count
            : 0

        snap.freeBytes = bytes(trulyFree)
        snap.activeBytes = bytes(stats.active_count)
        snap.inactiveBytes = bytes(stats.inactive_count)
        snap.wiredBytes = bytes(stats.wire_count)
        snap.speculativeBytes = bytes(stats.speculative_count)
        snap.purgeableBytes = bytes(stats.purgeable_count)
        snap.compressedBytes = bytes(stats.compressor_page_count)
        snap.pageIns = bytes64(stats.pageins)
        snap.pageOuts = bytes64(stats.pageouts)

        // Uygulama belleği = anonim sayfalar − boşaltılabilirler.
        // `internal_page_count` aktif + etkin olmayan anonim sayfaları birlikte kapsar;
        // `active_count` tek başına kullanılırsa kirli ama etkin olmayan sayfalar kaybolur.
        let anonymous = stats.internal_page_count > stats.purgeable_count
            ? stats.internal_page_count - stats.purgeable_count
            : 0
        snap.appMemoryBytes = bytes(anonymous)

        // Önbelleğe alınmış dosyalar = dosya destekli + boşaltılabilir sayfalar.
        snap.cachedFilesBytes = bytes(stats.external_page_count &+ stats.purgeable_count)

        let swap = SysctlKit.swapUsage
        snap.swapUsedBytes = swap.used
        snap.swapTotalBytes = swap.total

        snap.pressurePercent = pressure(from: snap)
        return snap
    }

    /// Activity Monitor'ün bellek baskısı grafiğine yakın bir tahmin.
    /// Çekirdek seviyesini (`kern.memorystatus_vm_pressure_level`) taban olarak alır,
    /// üstüne wired + sıkıştırılmış + swap ağırlığını bindirir.
    private func pressure(from snap: MemorySnapshot) -> Double {
        guard snap.totalBytes > 0 else { return 0 }

        let level = SysctlKit.int("kern.memorystatus_vm_pressure_level") ?? 1
        let floorValue: Double
        switch level {
        case 4: floorValue = 80      // critical
        case 2: floorValue = 50      // warning
        default: floorValue = 0      // normal
        }

        let hardUse = Double(snap.wiredBytes &+ snap.compressedBytes) / Double(snap.totalBytes)
        let swapPenalty = snap.swapUsedBytes > 0
            ? min(0.25, Double(snap.swapUsedBytes) / Double(snap.totalBytes))
            : 0
        let estimate = (hardUse + swapPenalty) * 100

        return min(100, max(floorValue, estimate))
    }
}

/// CPU yükü — örnekler arası fark alarak hesaplanır.
final class CPUService: @unchecked Sendable {
    private var previousTicks: [UInt32] = []
    private let lock = NSLock()

    func snapshot() -> CPUSnapshot {
        var snap = CPUSnapshot()
        let load = SysctlKit.loadAverage
        snap.loadAvg1 = load.0
        snap.loadAvg5 = load.1
        snap.loadAvg15 = load.2

        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &infoArray, &infoCount) == KERN_SUCCESS,
              let info = infoArray else { return snap }

        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var totals = [UInt32](repeating: 0, count: Int(CPU_STATE_MAX))
        for cpu in 0..<Int(cpuCount) {
            for state in 0..<Int(CPU_STATE_MAX) {
                totals[state] &+= UInt32(bitPattern: info[cpu * Int(CPU_STATE_MAX) + state])
            }
        }

        lock.lock()
        let previous = previousTicks
        previousTicks = totals
        lock.unlock()

        guard previous.count == totals.count else { return snap }

        var deltas = [Double](repeating: 0, count: totals.count)
        for i in 0..<totals.count {
            deltas[i] = Double(totals[i] &- previous[i])
        }
        let sum = deltas.reduce(0, +)
        guard sum > 0 else { return snap }

        snap.userPercent = (deltas[Int(CPU_STATE_USER)] + deltas[Int(CPU_STATE_NICE)]) / sum * 100
        snap.systemPercent = deltas[Int(CPU_STATE_SYSTEM)] / sum * 100
        snap.idlePercent = deltas[Int(CPU_STATE_IDLE)] / sum * 100
        return snap
    }
}
