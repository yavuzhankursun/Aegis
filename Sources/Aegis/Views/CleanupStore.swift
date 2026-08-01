import SwiftUI
import Observation

@MainActor
@Observable
final class CleanupStore {

    var targets: [CleanupTarget] = []
    var selection: Set<String> = []
    var expanded: Set<String> = []

    var isScanning = false
    var isCleaning = false
    var progress: Double = 0
    var progressLabel = ""
    var lastResult: CleanupResult?
    var lastScan: Date?

    private let service = CleanupService()
    private var scanTask: Task<Void, Never>?

    var totalFound: UInt64 { targets.reduce(0) { $0 &+ $1.totalBytes } }

    /// Seçim özeti **önbelleklenir**. Aksi halde her onay kutusu tıklamasında
    /// taranan tüm dosyalar üzerinde birkaç kez O(N) geçiş yapılıyordu
    /// (görünüm gövdesi bu değerleri tek çizimde 4+ kez okuyor).
    private(set) var selectedItems: [CleanupItem] = []
    private(set) var selectedBytes: UInt64 = 0
    private(set) var selectionContainsPermanent = false

    private func refreshSelectionSummary() {
        var items: [CleanupItem] = []
        var bytes: UInt64 = 0
        var permanent = false
        for target in targets {
            for item in target.items where selection.contains(item.id) {
                items.append(item)
                bytes &+= item.bytes
                if !permanent, SafetyGuard.isInsideTrash(item.url) { permanent = true }
            }
        }
        selectedItems = items
        selectedBytes = bytes
        selectionContainsPermanent = permanent
    }

    // MARK: - Tarama

    func scan() {
        guard !isScanning else { return }
        scanTask?.cancel()
        isScanning = true
        progress = 0
        progressLabel = "Başlıyor…"
        lastResult = nil

        scanTask = Task { [weak self] in
            guard let self else { return }

            let service = self.service
            let stream = AsyncStream<(String, Double)> { continuation in
                Task.detached(priority: .utility) {
                    let found = service.scan(budget: 60) { label, value in
                        continuation.yield((label, value))
                    }
                    continuation.yield(("__done__", 1))
                    continuation.finish()
                    await MainActor.run { [weak self] in
                        self?.apply(found)
                    }
                }
            }

            for await (label, value) in stream {
                if Task.isCancelled { break }
                if label != "__done__" {
                    self.progressLabel = label
                    self.progress = value
                }
            }
        }
    }

    private func apply(_ found: [CleanupTarget]) {
        targets = found.filter { !$0.items.isEmpty }
        // Yalnızca "Güvenli" işaretli hedefler önceden seçilir.
        selection = Set(targets.filter { $0.risk == .safe }.flatMap { $0.items.map(\.id) })
        expanded = Set(targets.prefix(2).map(\.id))
        refreshSelectionSummary()
        isScanning = false
        progress = 1
        progressLabel = "Tamamlandı"
        lastScan = Date()
        scanTask = nil
    }

    // MARK: - Seçim

    func isSelected(_ item: CleanupItem) -> Bool { selection.contains(item.id) }

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        refreshSelectionSummary()
    }

    func selectionState(of target: CleanupTarget) -> SelectionState {
        let ids = Set(target.items.map(\.id))
        let chosen = ids.intersection(selection)
        if chosen.isEmpty { return .none }
        if chosen.count == ids.count { return .all }
        return .partial
    }

    func toggleAll(in target: CleanupTarget) {
        let ids = target.items.map(\.id)
        if selectionState(of: target) == .all {
            ids.forEach { selection.remove($0) }
        } else {
            ids.forEach { selection.insert($0) }
        }
        refreshSelectionSummary()
    }

    func selectSafeOnly() {
        selection = Set(targets.filter { $0.risk == .safe }.flatMap { $0.items.map(\.id) })
        refreshSelectionSummary()
    }

    func clearSelection() {
        selection.removeAll()
        refreshSelectionSummary()
    }

    enum SelectionState { case none, partial, all }

    // MARK: - Temizlik

    func clean() {
        guard !isCleaning, !selectedItems.isEmpty else { return }
        isCleaning = true
        let items = selectedItems

        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) { [service] in
                service.clean(items: items)
            }.value

            self.lastResult = result
            self.isCleaning = false
            self.selection.removeAll()
            self.refreshSelectionSummary()
            // Temizlik sonrası listeyi tazele ki silinenler kaybolsun.
            self.scan()
        }
    }

}
