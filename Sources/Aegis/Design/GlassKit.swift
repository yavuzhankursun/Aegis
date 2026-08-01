import SwiftUI
import AppKit

// MARK: - Liquid Glass yüzeyler

/// Liquid Glass yüzeyi. `AEGIS_PLAIN=1` ile şeffaflık azaltılabilir
/// (sistemin "Şeffaflığı azalt" erişilebilirlik ayarını da dinler).
struct SurfaceStyle: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    static let plain: Bool = {
        if ProcessInfo.processInfo.environment["AEGIS_PLAIN"] == "1" { return true }
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }()

    func body(content: Content) -> some View {
        if Self.plain {
            content.background(Theme.gunmetal.opacity(0.92), in: .rect(cornerRadius: cornerRadius))
        } else {
            content.glassEffect(
                tint.map { Glass.regular.tint($0.opacity(0.16)) } ?? Glass.regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        }
    }
}

/// Uygulamanın temel yüzeyi: cam + üstte ince ışık çizgisi + derinlik gölgesi.
/// İmleç üzerine gelince çok hafif yükselir — sadece hover sırasında animasyon
/// çalışır, boştayken hiçbir kare çizilmez.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 18
    var tint: Color? = nil
    var lifts: Bool = true
    @ViewBuilder var content: Content

    @State private var hovering = false

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SurfaceStyle(cornerRadius: cornerRadius, tint: tint))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(hovering ? 0.34 : 0.20),
                                (tint ?? Theme.steel).opacity(0.10),
                                Color.white.opacity(0.03),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            }
            .shadow(color: .black.opacity(hovering ? 0.34 : 0.24),
                    radius: hovering ? 16 : 10, x: 0, y: hovering ? 8 : 5)
            .scaleEffect(hovering && lifts ? 1.004 : 1.0)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { if lifts { hovering = $0 } }
    }
}

/// Başlık + simge + içerik düzenli kart.
struct GlassSection<Content: View>: View {
    let title: String
    var symbol: String
    var accent: Color = Theme.aqua
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                        .background(accent.opacity(0.15), in: .rect(cornerRadius: 8))
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer(minLength: 8)
                    if let trailing { trailing }
                }
                content
            }
        }
    }
}

// MARK: - Arka plan

/// Mesh gradyan arka plan.
///
/// **Maliyet notu:** sürekli animasyonlu + blur'lu bir tam ekran mesh gradyan
/// tek başına %10 CPU yiyordu. Bu yüzden gradyan statik çizilir ve
/// `drawingGroup()` ile tek seferde rasterize edilir — boştayken maliyeti ~%0.
/// Hareket hissi, üstteki cam katmanların kendi canlı efektlerinden gelir.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Theme.void)

            MeshGradient(
                width: 3, height: 3,
                points: [
                    .init(0, 0), .init(0.52, 0), .init(1, 0),
                    .init(0, 0.46), .init(0.44, 0.55), .init(1, 0.52),
                    .init(0, 1), .init(0.58, 1), .init(1, 1),
                ],
                colors: [
                    Theme.steel.opacity(0.42), Theme.gunmetal, Theme.cyan.opacity(0.24),
                    Theme.gunmetal, Theme.void, Theme.steel.opacity(0.22),
                    Theme.void, Theme.gunmetal, Theme.teal.opacity(0.16),
                ],
                smoothsColors: true
            )
            .drawingGroup()
            .ignoresSafeArea()

            // İnce teknik ızgara — kokpit hissi, tek seferde çizilir.
            GridOverlay()
                .opacity(0.05)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

/// Statik ölçüm ızgarası.
private struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 42
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(Theme.titanium), lineWidth: 0.5)
        }
    }
}

// MARK: - Küçük parçalar

struct Pill: View {
    let text: String
    var color: Color = Theme.aqua
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(.system(size: 10.5, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.16), in: .capsule)
        .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 0.6))
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// Yatay dolum çubuğu.
struct MeterBar: View {
    var fraction: Double
    var gradient: LinearGradient
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.6))
                Capsule()
                    .fill(gradient)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
                    .animation(.easeOut(duration: 0.25), value: fraction)
            }
        }
        .frame(height: height)
    }
}

/// Çok segmentli çubuk (bellek dağılımı, disk kategorileri).
struct SegmentedBar: View {
    struct Segment: Identifiable {
        var id: String { label }
        let value: Double
        let color: Color
        let label: String
    }

    let segments: [Segment]
    var height: CGFloat = 12

    private var total: Double { max(segments.reduce(0) { $0 + $1.value }, 0.0001) }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, segment.value / total * (geo.size.width - CGFloat(segments.count) * 1.5)))
                }
                Spacer(minLength: 0)
            }
            .clipShape(Capsule())
            .background(Capsule().fill(.quaternary.opacity(0.5)))
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: total)
    }
}
