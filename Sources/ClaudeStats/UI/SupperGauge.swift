// Vendored copy of the SupperGauge package (../supperGauge), so this public repo builds on its own.
// Make changes there first and copy the file back.

import SwiftUI

/// Colours and image for one colour scheme. A gauge takes one for light mode and one for dark mode,
/// and switches between them by itself.
public struct SupperGaugeAppearance {
    /// Unfilled part of every ring.
    public var trackColor: Color
    /// Filled part of every ring, the part that shows the value.
    public var progressColor: Color
    /// Filled part of each ring, outermost first. Rings without an entry use `progressColor`.
    public var ringColors: [Color]
    /// Line drawn at the `marker` position.
    public var markerColor: Color
    /// Shown in the hole of the rings, scaled to fit 54% of the hole's diameter.
    /// It is centred by its frame, so the visual centre of the drawing must be the centre of the image.
    public var image: Image

    public init(
        trackColor: Color,
        progressColor: Color,
        ringColors: [Color] = [],
        markerColor: Color,
        image: Image
    ) {
        self.trackColor = trackColor
        self.progressColor = progressColor
        self.ringColors = ringColors
        self.markerColor = markerColor
        self.image = image
    }

    /// Default for light mode: dark grey rings and the dark spark image.
    public static let light = SupperGaugeAppearance(
        trackColor: Color(white: 0.29).opacity(0.15),
        progressColor: Color(white: 0.29),
        markerColor: .accentColor,
        image: .bundled("spark-light")
    )

    /// Default for dark mode: light grey rings and the light spark image.
    public static let dark = SupperGaugeAppearance(
        trackColor: Color(white: 0.91).opacity(0.2),
        progressColor: Color(white: 0.91),
        markerColor: .accentColor,
        image: .bundled("spark-dark")
    )
}

extension SupperGaugeAppearance {
    func progressColor(ring index: Int) -> Color {
        ringColors.indices.contains(index) ? ringColors[index] : progressColor
    }
}

extension Image {
    // Image(_:bundle:) only looks in asset catalogs, and `swift build` does not compile them,
    // so loose PNGs in the package have to be loaded by URL.
    static func bundled(_ name: String) -> Image {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let nsImage = NSImage(contentsOf: url)
        else {
            return Image(systemName: "questionmark.circle")
        }
        return Image(nsImage: nsImage)
    }
}

/// A ring gauge for 0...100 values with an image in the middle. Shows one or more concentric rings
/// and an optional marker line. It is always square and fills the space it is given.
public struct SupperGauge: View {
    private let values: [Double]
    private let marker: Double?
    private let light: SupperGaugeAppearance
    private let dark: SupperGaugeAppearance
    private let lineWidth: CGFloat?
    private let markerWidth: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - value: 0...100. Values outside the range are clamped.
    ///   - marker: 0...100. Draws a line across the ring at this position.
    ///   - light: Colours and image used in light mode.
    ///   - dark: Colours and image used in dark mode.
    ///   - lineWidth: Ring thickness in points. When nil it scales with the gauge (12% of its side).
    ///   - markerWidth: Thickness of the marker line in points. When nil it is 15% of `lineWidth`, at least 1.5.
    public init(
        value: Double,
        marker: Double? = nil,
        light: SupperGaugeAppearance = .light,
        dark: SupperGaugeAppearance = .dark,
        lineWidth: CGFloat? = nil,
        markerWidth: CGFloat? = nil
    ) {
        self.init(values: [value], marker: marker, light: light, dark: dark, lineWidth: lineWidth, markerWidth: markerWidth)
    }

    /// Shows one concentric ring per value, outermost first. All rings share the space of a single ring,
    /// so the gauge keeps the same size whatever the number of values.
    /// - Parameters:
    ///   - values: 0...100 each. Values outside the range are clamped.
    ///   - marker: 0...100. Draws a line across all the rings at this position.
    ///   - light: Colours and image used in light mode.
    ///   - dark: Colours and image used in dark mode.
    ///   - lineWidth: Total thickness in points of all rings plus the gaps between them.
    ///     When nil it scales with the gauge (12% of its side).
    ///   - markerWidth: Thickness of the marker line in points. When nil it is 15% of `lineWidth`, at least 1.5.
    public init(
        values: [Double],
        marker: Double? = nil,
        light: SupperGaugeAppearance = .light,
        dark: SupperGaugeAppearance = .dark,
        lineWidth: CGFloat? = nil,
        markerWidth: CGFloat? = nil
    ) {
        precondition(!values.isEmpty, "SupperGauge needs at least one value")
        self.values = values
        self.marker = marker
        self.light = light
        self.dark = dark
        self.lineWidth = lineWidth
        self.markerWidth = markerWidth
    }

    private var fractions: [Double] {
        values.map(Self.fraction)
    }

    private var markerFraction: Double? {
        marker.map(Self.fraction)
    }

    private static func fraction(_ percent: Double) -> Double {
        min(max(percent, 0), 100) / 100
    }

    private var appearance: SupperGaugeAppearance {
        colorScheme == .dark ? dark : light
    }

    public var body: some View {
        SquareLayout {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let band = lineWidth ?? side * 0.12
                let count = CGFloat(fractions.count)
                // With two rings this gives 40% ring, 20% gap, 40% ring.
                let gap = count > 1 ? band * 0.2 : 0
                let ringWidth = (band - gap * (count - 1)) / count
                // The marker sticks out of the rings on both sides. The rings shrink to make room for it,
                // so nothing is drawn outside the gauge's frame.
                let markerOverhang = max(1, band * 0.15)
                let ringsSide = side - 2 * markerOverhang
                let innerDiameter = ringsSide - 2 * band

                ZStack {
                    ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                        // Diameter of the stroke's centre line; the stroke spreads half its width to each side.
                        let diameter = ringsSide - ringWidth - 2 * CGFloat(index) * (ringWidth + gap)

                        ZStack {
                            Circle()
                                .stroke(appearance.trackColor, lineWidth: ringWidth)

                            Circle()
                                .trim(from: 0, to: fraction)
                                .stroke(appearance.progressColor(ring: index), style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                                // Start at 12 o'clock instead of 3 o'clock.
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: diameter, height: diameter)
                    }

                    if let markerFraction {
                        // A rotated rectangle instead of a Path: rotation animates along the arc,
                        // while a Path would morph in a straight line between the two positions.
                        Rectangle()
                            .fill(appearance.markerColor)
                            .frame(width: markerWidth ?? max(1.5, band * 0.15), height: band + 2 * markerOverhang)
                            .offset(y: -(ringsSide - band) / 2)
                            .rotationEffect(.degrees(markerFraction * 360))
                    }

                    appearance.image
                        .resizable()
                        .scaledToFit()
                        // 0.54 rather than 0.5 because the spark PNGs carry transparent padding (added to centre
                        // the star's hub); this keeps the star itself at about half the hole.
                        .frame(width: innerDiameter * 0.54, height: innerDiameter * 0.54)
                }
                .frame(width: side, height: side)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: fractions)
        .animation(.easeInOut(duration: 0.3), value: markerFraction)
        .accessibilityElement()
        .accessibilityValue(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = fractions.map { "\(Int($0 * 100)) percent" }
        if let markerFraction {
            parts.append("marker at \(Int(markerFraction * 100)) percent")
        }
        return parts.joined(separator: ", ")
    }
}

// A GeometryReader alone reports a tiny ideal size. With only `.frame(width:)` in a window that sizes to
// its content, the gauge got no height and collapsed to about 24 pt. This layout takes the missing side
// from the given one, so the gauge is always square at the size it is given.
private struct SquareLayout: Layout {
    // Used only when neither width nor height is given.
    private let defaultSide: CGFloat = 100

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let given = [proposal.width, proposal.height].compactMap { $0 }.filter(\.isFinite)
        let side = given.min() ?? defaultSide
        return CGSize(width: side, height: side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let side = min(bounds.width, bounds.height)
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(width: side, height: side)
            )
        }
    }
}

#Preview("Light") {
    HStack(spacing: 24) {
        SupperGauge(value: 72).frame(width: 80)
        SupperGauge(values: [20, 40]).frame(width: 80)
        SupperGauge(values: [20, 40], marker: 65).frame(width: 120)
    }
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Ring colours") {
    var light = SupperGaugeAppearance.light
    light.ringColors = [.blue, .orange]
    var dark = SupperGaugeAppearance.dark
    dark.ringColors = [.cyan, .yellow]
    return SupperGauge(values: [20, 40], marker: 65, light: light, dark: dark)
        .frame(width: 120)
        .padding()
}

#Preview("Dark") {
    HStack(spacing: 24) {
        SupperGauge(value: 72).frame(width: 80)
        SupperGauge(values: [20, 40]).frame(width: 80)
        SupperGauge(values: [20, 40], marker: 65).frame(width: 120)
    }
    .padding()
    .preferredColorScheme(.dark)
}
