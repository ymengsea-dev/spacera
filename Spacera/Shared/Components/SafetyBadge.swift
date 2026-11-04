import SwiftUI

struct SafetyBadge: View {
    var level: SafetyLevel

    var body: some View {
        Label(level.title, systemImage: level.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(level.color.mix(with: Theme.ink, by: 0.25))
            .background(level.color.opacity(0.16), in: Capsule())
            .accessibilityLabel("Safety: \(level.title)")
    }
}

struct SizeLabel: View {
    var bytes: Int64
    var font: Font = .body

    var body: some View {
        Text(bytes.formattedBytes)
            .font(font)
            .monospacedDigit()
    }
}

/// A thin horizontal bar made of coloured segments.
struct SegmentBar: View {
    struct Segment: Identifiable {
        var id: String
        var value: Double
        var color: Color
    }

    var segments: [Segment]
    var total: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: height >= 10 ? 2 : 1) {
                ForEach(segments) { segment in
                    if segment.value > 0, total > 0 {
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(1, geo.size.width * segment.value / total))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Theme.rule)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
