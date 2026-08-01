import Foundation

/// Disk birimleri ve kategori bazlı kullanım. Yalnızca okur.
struct StorageService: Sendable {

    func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
            .volumeIsRemovableKey, .volumeIsBrowsableKey, .volumeLocalizedFormatDescriptionKey
        ]

        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var result: [VolumeInfo] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity, total > 0 else { continue }

            let free = values.volumeAvailableCapacity ?? 0
            let important = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) } ?? UInt64(max(0, free))

            result.append(VolumeInfo(
                name: values.volumeName ?? url.lastPathComponent,
                path: url.path,
                totalBytes: UInt64(total),
                freeBytes: UInt64(max(0, free)),
                availableForImportantBytes: important,
                isInternal: values.volumeIsInternal ?? true,
                isRemovable: values.volumeIsRemovable ?? false,
                fileSystem: values.volumeLocalizedFormatDescription ?? "APFS"
            ))
        }

        // Ana disk en üstte.
        return result.sorted { lhs, rhs in
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal }
            return lhs.totalBytes > rhs.totalBytes
        }
    }

    /// Kullanıcı klasörlerinin kabaca boyutu. `du` yerine dosya sayımı kullanır
    /// ki izin verilmeyen dizinlerde sessizce atlansın.
    func homeCategories(progress: (@Sendable (String) -> Void)? = nil) -> [StorageCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let targets: [(String, String, String)] = [
            ("Uygulamalar", "/Applications", "app.badge"),
            ("Belgeler", home.appendingPathComponent("Documents").path, "doc.text"),
            ("İndirilenler", home.appendingPathComponent("Downloads").path, "arrow.down.circle"),
            ("Masaüstü", home.appendingPathComponent("Desktop").path, "menubar.dock.rectangle"),
            ("Fotoğraflar", home.appendingPathComponent("Pictures").path, "photo"),
            ("Filmler", home.appendingPathComponent("Movies").path, "film"),
            ("Müzik", home.appendingPathComponent("Music").path, "music.note"),
            ("Kitaplık", home.appendingPathComponent("Library").path, "books.vertical"),
        ]

        // Her klasöre ayrı bir süre bütçesi: devasa bir Fotoğraflar kitaplığı
        // taramanın tamamını kilitlemesin.
        return targets.compactMap { name, path, symbol in
            progress?(name)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let bytes = FileSizer.directorySize(at: URL(fileURLWithPath: path),
                                                maxDepth: 12,
                                                deadline: Date().addingTimeInterval(12))
            guard bytes > 0 else { return nil }
            return StorageCategory(name: name, bytes: bytes, symbol: symbol)
        }.sorted { $0.bytes > $1.bytes }
    }
}

/// Dizin boyutu hesaplayıcı — sembolik bağları takip etmez, izin hatalarını yutar.
enum FileSizer {

    static func directorySize(at url: URL, maxDepth: Int = 32, deadline: Date? = nil) -> UInt64 {
        var total: UInt64 = 0
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                          .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]

        // Paket içlerine de gireriz: `.app`, `.photoslibrary`, `.sparsebundle` gibi
        // paketler atlanırsa Uygulamalar ve Fotoğraflar klasörleri 0 bayt görünür.
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }   // erişilemeyeni atla, çökme
        ) else { return 0 }

        var checkCounter = 0
        for case let child as URL in enumerator {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            checkCounter += 1
            if let deadline, checkCounter % 512 == 0, Date() > deadline { break }

            guard let values = try? child.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true { continue }
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total &+= UInt64(max(0, size))
        }
        return total
    }

    static func size(of url: URL, deadline: Date? = nil) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory == true { return directorySize(at: url, deadline: deadline) }
        return UInt64(max(0, values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0))
    }
}
