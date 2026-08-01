import SwiftUI

/// **Aegis Skoru** — beş ölçümü tek bir sayıya indiren ana gösterge.
/// Halka açılışta bir kez çizilir, sonra yalnızca değer değiştiğinde
/// 0,28 sn'lik tek bir geçiş yapar.
struct ScoreCard: View {
    @Environment(SystemMonitor.self) private var monitor
    @State private var appeared = false

    private var score: AegisScore { monitor.score }
    private var accent: Color { Theme.color(forScore: score.total) }

    var body: some View {
        GlassCard(tint: accent) {
            HStack(spacing: 26) {
                dial
                Divider().frame(height: 96).opacity(0.15)
                breakdown
                Spacer(minLength: 0)
                verdict
            }
        }
    }

    // MARK: - Kadran

    private var dial: some View {
        ZStack {
            ArcGauge(
                fraction: appeared ? score.total / 100 : 0,
                gradient: Theme.gradient([accent, accent.opacity(0.45)]),
                lineWidth: 11
            ) {
                VStack(spacing: -2) {
                    Text("\(Int(score.total.rounded()))")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("AEGIS SKORU")
                        .font(.system(size: 7.5, weight: .bold))
                        .kerning(1.1)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 118, height: 118)

            // Kadran çentikleri — statik, tek seferde çizilir.
            TickRing().frame(width: 138, height: 138).opacity(0.35)
        }
        .onAppear {
            // Açılış animasyonu: halka sıfırdan gerçek değere yürür.
            withAnimation(.smooth(duration: 0.9)) { appeared = true }
        }
    }

    // MARK: - Bileşenler

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(score.components) { component in
                HStack(spacing: 9) {
                    Image(systemName: component.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.color(forScore: component.score))
                        .frame(width: 15)

                    Text(component.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 66, alignment: .leading)

                    MeterBar(
                        fraction: component.score / 100,
                        gradient: Theme.gradient([Theme.color(forScore: component.score),
                                                  Theme.color(forScore: component.score).opacity(0.45)]),
                        height: 5
                    )
                    .frame(width: 128)

                    Text("\(Int(component.score))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.color(forScore: component.score))
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)

                    Text(component.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var verdict: some View {
        VStack(alignment: .trailing, spacing: 7) {
            Text(score.grade.uppercased())
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(accent)

            if let weakest = score.weakest, weakest.score < 85 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("En zayıf halka")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                    Label(weakest.name, systemImage: weakest.symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.color(forScore: weakest.score))
                }
            } else {
                Text("Tüm sistemler yeşil")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.teal)
            }
        }
        .frame(width: 150, alignment: .trailing)
    }
}

/// Kadranın etrafındaki ölçek çentikleri.
private struct TickRing: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2
            for index in 0...40 {
                let progress = Double(index) / 40
                let angle = Angle.degrees(140 + progress * 260).radians
                let major = index % 5 == 0
                let length: CGFloat = major ? 7 : 3.5
                let start = CGPoint(x: center.x + cos(angle) * (outer - length),
                                    y: center.y + sin(angle) * (outer - length))
                let end = CGPoint(x: center.x + cos(angle) * outer,
                                  y: center.y + sin(angle) * outer)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path,
                               with: .color(Theme.titanium.opacity(major ? 0.9 : 0.45)),
                               lineWidth: major ? 1.4 : 0.8)
            }
        }
    }
}
