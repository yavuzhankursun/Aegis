import SwiftUI

/// Halka göstergesi — merkezinde değer, altında etiket.
struct RingGauge<Center: View>: View {
    var fraction: Double
    var gradient: LinearGradient
    var lineWidth: CGFloat = 12
    var trackOpacity: Double = 0.18
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(trackOpacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.28), value: fraction)

            center
        }
    }
}

/// Yarım daire (240°) gösterge — pil ve baskı ekranlarında.
struct ArcGauge<Center: View>: View {
    var fraction: Double
    var gradient: LinearGradient
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: Center

    private let span: Double = 0.72   // toplam 259°

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: span)
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(90 + (1 - span) * 180))

            Circle()
                .trim(from: 0, to: span * max(0.001, min(1, fraction)))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(90 + (1 - span) * 180))
                .animation(.easeOut(duration: 0.28), value: fraction)

            center
        }
    }
}

/// Zaman serisi mini grafik.
struct Sparkline: View {
    var values: [Double]
    var gradient: LinearGradient
    var filled: Bool = true
    var maximum: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            ZStack {
                if filled, points.count > 1 {
                    fillPath(points, in: geo.size)
                        .fill(LinearGradient(colors: [Theme.aqua.opacity(0.28), .clear],
                                             startPoint: .top, endPoint: .bottom))
                }
                if points.count > 1 {
                    linePath(points)
                        .stroke(gradient, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let upper = max(maximum ?? (values.max() ?? 1), 0.0001)
        let lower = 0.0
        let range = max(upper - lower, 0.0001)

        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
            let clamped = min(max(value, lower), upper)
            let y = size.height - CGFloat((clamped - lower) / range) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func fillPath(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = linePath(points)
        path.addLine(to: CGPoint(x: points.last!.x, y: size.height))
        path.addLine(to: CGPoint(x: points.first!.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// Çekirdek yükü için minik dikey çubuklar.
struct BarSeries: View {
    var values: [Double]
    var color: Color
    var spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color.opacity(0.35 + 0.65 * min(1, value)))
                        .frame(width: width, height: max(2, geo.size.height * min(1, value)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Büyük sayı + etiket bloğu.
struct StatBlock: View {
    let value: String
    let label: String
    var symbol: String? = nil
    var color: Color = Theme.text
    var size: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(value)
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
