import SwiftUI

/// Karbon–çelik temalı, enstrüman paneli hissi veren palet.
/// Uygulama daima koyu görünümde çalışır: kokpit arayüzünde kontrast
/// ve okunabilirlik sistem temasına bırakılmayacak kadar kritik.
enum Theme {

    // MARK: - Yüzeyler

    static let void       = Color(red: 0.035, green: 0.045, blue: 0.062)   // #090B10
    static let carbon     = Color(red: 0.063, green: 0.078, blue: 0.098)   // #101419
    static let gunmetal   = Color(red: 0.106, green: 0.125, blue: 0.153)   // #1B2027

    // MARK: - Metin

    static let text          = Color(red: 0.90, green: 0.93, blue: 0.96)
    static let textSecondary = Color(red: 0.58, green: 0.63, blue: 0.70)
    static let textTertiary  = Color(red: 0.40, green: 0.45, blue: 0.52)

    // MARK: - Aksanlar

    static let cyan     = Color(red: 0.13, green: 0.83, blue: 0.93)   // elektrik mavisi
    static let steel    = Color(red: 0.35, green: 0.55, blue: 0.78)   // çelik mavi
    static let teal     = Color(red: 0.08, green: 0.72, blue: 0.65)
    static let lime     = Color(red: 0.51, green: 0.83, blue: 0.29)
    static let amber    = Color(red: 0.96, green: 0.68, blue: 0.13)
    static let orange   = Color(red: 0.95, green: 0.45, blue: 0.14)
    static let crimson  = Color(red: 0.90, green: 0.26, blue: 0.24)
    static let titanium = Color(red: 0.62, green: 0.67, blue: 0.73)
    static let plasma   = Color(red: 0.51, green: 0.47, blue: 0.88)   // koyu indigo

    // Eski isimlerin karşılıkları (tek noktadan yönetim)
    static var aqua: Color { cyan }
    static var mint: Color { teal }
    static var indigo: Color { steel }
    static var violet: Color { plasma }
    static var coral: Color { orange }
    static var rose: Color { crimson }

    // MARK: - Gradyanlar

    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let good    = gradient([teal, cyan])
    static let neutral = gradient([cyan, steel])
    static let warn    = gradient([amber, orange])
    static let bad     = gradient([orange, crimson])

    static func gradient(forHealth grade: HealthGrade) -> LinearGradient {
        switch grade {
        case .excellent: return good
        case .good: return gradient([cyan, teal])
        case .fair: return warn
        case .critical: return bad
        }
    }

    static func color(forPressure level: PressureLevel) -> Color {
        switch level {
        case .normal: return teal
        case .warning: return amber
        case .critical: return crimson
        }
    }

    static func color(forEnergy band: EnergyBand) -> Color {
        switch band {
        case .low: return teal
        case .moderate: return cyan
        case .high: return amber
        case .severe: return orange
        }
    }

    /// Dolulukta yeşilden kırmızıya geçen tek renk.
    static func usageColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: return teal
        case ..<0.75: return cyan
        case ..<0.88: return amber
        default: return crimson
        }
    }

    /// 0–100 skor için renk.
    static func color(forScore score: Double) -> Color {
        switch score {
        case 85...: return teal
        case 70..<85: return cyan
        case 50..<70: return amber
        default: return crimson
        }
    }
}

// MARK: - Biçimlendirme

enum Format {

    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))))
    }

    static func bytesCompact(_ value: UInt64) -> String {
        let gb = Double(value) / 1_000_000_000
        if gb >= 100 { return String(format: "%.0f GB", gb) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(value) / 1_000_000
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return String(format: "%.0f KB", Double(value) / 1000)
    }

    /// Türkçe yazım: yüzde işareti başta, ondalık ayırıcı virgül → `%99,6`.
    /// Tek giriş noktası; aynı metrik iki farklı yerde farklı görünmesin.
    static func percent(_ value: Double, decimals: Int = 0) -> String {
        let number = String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
        return "%" + number
    }

    static func minutes(_ value: Int) -> String {
        guard value >= 0 else { return "hesaplanıyor" }
        let hours = value / 60
        let mins = value % 60
        if hours == 0 { return "\(mins) dk" }
        return "\(hours) sa \(mins) dk"
    }

    static func uptime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days) gün \(hours) sa" }
        if hours > 0 { return "\(hours) sa \(minutes) dk" }
        return "\(minutes) dk"
    }

    static func hours(_ value: Int) -> String {
        if value >= 24 {
            let days = value / 24
            return "\(days) gün \(value % 24) sa"
        }
        return "\(value) sa"
    }

    static func temperature(_ celsius: Double) -> String {
        celsius > 0 ? String(format: "%.1f°C", celsius) : "—"
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: value)
    }
}
