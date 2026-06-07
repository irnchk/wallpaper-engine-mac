import AppKit

struct AudioResponsiveOverlayStyle {
    enum Source {
        case systemDefault
        case workshopAudioBars
    }

    enum Placement {
        case bottom
        case top
        case left
        case right
        case circleInner
        case circleOuter
        case centerHorizontal
        case centerVertical
        case stereoHorizontal
        case stereoVertical
    }

    let source: Source
    let placement: Placement
    let barCount: Int
    let color: NSColor
    let lowerBound: CGFloat
    let upperBound: CGFloat
    let spacing: CGFloat
    let opacity: CGFloat
    let angleStart: CGFloat
    let angleEnd: CGFloat

    static let systemDefault = AudioResponsiveOverlayStyle(
        source: .systemDefault,
        placement: .bottom,
        barCount: 28,
        color: .systemTeal,
        lowerBound: 0,
        upperBound: 0.18,
        spacing: 0.18,
        opacity: 0.8,
        angleStart: 0,
        angleEnd: 360
    )
}

@MainActor
final class AudioResponsiveOverlayView: NSView {
    private var smoothedLevel: CGFloat = 0

    var style = AudioResponsiveOverlayStyle.systemDefault {
        didSet {
            needsDisplay = true
        }
    }

    var isAudioResponsiveEnabled = false {
        didSet {
            isHidden = !isAudioResponsiveEnabled
            if !isAudioResponsiveEnabled {
                update(level: 0)
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(level: Double) {
        let clamped = CGFloat(min(max(level, 0), 1))
        smoothedLevel = smoothedLevel * 0.72 + clamped * 0.28
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isAudioResponsiveEnabled, bounds.width > 0, bounds.height > 0 else {
            return
        }

        switch style.source {
        case .systemDefault:
            drawEdgePulse()
            drawSystemBars()
        case .workshopAudioBars:
            drawWorkshopAudioBars()
        }
    }

    private func drawEdgePulse() {
        let alpha = min(0.18, 0.04 + smoothedLevel * 0.18)
        let gradient = NSGradient(colors: [
            NSColor.systemTeal.withAlphaComponent(alpha),
            NSColor.systemPink.withAlphaComponent(alpha * 0.55),
            NSColor.clear
        ])
        gradient?.draw(in: bounds.insetBy(dx: -bounds.width * 0.08, dy: -bounds.height * 0.08), angle: 90)
    }

    private func drawSystemBars() {
        let barCount = AudioResponsiveOverlayStyle.systemDefault.barCount
        let horizontalInset = max(32, bounds.width * 0.08)
        let availableWidth = bounds.width - horizontalInset * 2
        guard availableWidth > 0 else {
            return
        }

        let gap: CGFloat = 5
        let barWidth = max(3, (availableWidth - CGFloat(barCount - 1) * gap) / CGFloat(barCount))
        let baseline = max(22, bounds.height * 0.035)
        let maxHeight = min(128, bounds.height * 0.18)

        for index in 0..<barCount {
            let seed = barSeed(index)
            let wave = 0.72 + 0.28 * sin(CGFloat(index) * 0.85 + smoothedLevel * 9)
            let height = max(3, maxHeight * smoothedLevel * seed * wave)
            let x = horizontalInset + CGFloat(index) * (barWidth + gap)
            let rect = NSRect(x: x, y: baseline, width: barWidth, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            let hueMix = CGFloat(index) / CGFloat(max(1, barCount - 1))
            let color = NSColor(
                calibratedHue: 0.46 + hueMix * 0.42,
                saturation: 0.72,
                brightness: 0.92,
                alpha: 0.28 + smoothedLevel * 0.52
            )
            color.setFill()
            path.fill()
        }
    }

    private func drawWorkshopAudioBars() {
        let barCount = max(1, min(style.barCount, 200))
        let color = (style.color.usingColorSpace(.deviceRGB) ?? style.color)
            .withAlphaComponent(min(max(style.opacity, 0.05), 1))

        switch style.placement {
        case .bottom:
            drawVerticalWorkshopBars(barCount: barCount, color: color, mode: .bottom)
        case .top:
            drawVerticalWorkshopBars(barCount: barCount, color: color, mode: .top)
        case .centerHorizontal:
            drawVerticalWorkshopBars(barCount: barCount, color: color, mode: .center)
        case .stereoHorizontal:
            drawVerticalWorkshopBars(barCount: barCount, color: color, mode: .stereo)
        case .left:
            drawHorizontalWorkshopBars(barCount: barCount, color: color, mode: .left)
        case .right:
            drawHorizontalWorkshopBars(barCount: barCount, color: color, mode: .right)
        case .centerVertical:
            drawHorizontalWorkshopBars(barCount: barCount, color: color, mode: .center)
        case .stereoVertical:
            drawHorizontalWorkshopBars(barCount: barCount, color: color, mode: .stereo)
        case .circleInner:
            drawRadialWorkshopBars(barCount: barCount, color: color, mode: .inner)
        case .circleOuter:
            drawRadialWorkshopBars(barCount: barCount, color: color, mode: .outer)
        }
    }

    private enum VerticalWorkshopBarMode {
        case bottom
        case top
        case center
        case stereo
    }

    private enum HorizontalWorkshopBarMode {
        case left
        case right
        case center
        case stereo
    }

    private enum RadialWorkshopBarMode {
        case inner
        case outer
    }

    private func drawVerticalWorkshopBars(
        barCount: Int,
        color: NSColor,
        mode: VerticalWorkshopBarMode
    ) {
        let horizontalInset = max(0, bounds.width * 0.015)
        let availableWidth = bounds.width - horizontalInset * 2
        guard availableWidth > 0 else {
            return
        }

        let rawSlotWidth = availableWidth / CGFloat(barCount)
        let gap = max(0, rawSlotWidth * min(max(style.spacing, 0), 0.9))
        let barWidth = max(1, rawSlotWidth - gap)
        let valueBounds = normalizedValueBounds()
        let lowerHeight = bounds.height * valueBounds.lower
        let upperHeight = bounds.height * valueBounds.upper

        for index in 0..<barCount {
            let volume = workshopBarLevel(index: index, barCount: barCount)
            let height = max(1, lowerHeight + (upperHeight - lowerHeight) * volume)
            let x = horizontalInset + CGFloat(index) * rawSlotWidth + gap / 2
            switch mode {
            case .bottom:
                fillRect(NSRect(x: x, y: 0, width: barWidth, height: height), color: color)
            case .top:
                fillRect(NSRect(x: x, y: bounds.height - height, width: barWidth, height: height), color: color)
            case .center:
                fillRect(NSRect(x: x, y: (bounds.height - height) / 2, width: barWidth, height: height), color: color)
            case .stereo:
                let halfHeight = max(1, height / 2)
                let centerY = bounds.midY
                fillRect(NSRect(x: x, y: centerY, width: barWidth, height: halfHeight), color: color)
                fillRect(NSRect(x: x, y: centerY - halfHeight, width: barWidth, height: halfHeight), color: color)
            }
        }
    }

    private func drawHorizontalWorkshopBars(
        barCount: Int,
        color: NSColor,
        mode: HorizontalWorkshopBarMode
    ) {
        let verticalInset = max(0, bounds.height * 0.015)
        let availableHeight = bounds.height - verticalInset * 2
        guard availableHeight > 0 else {
            return
        }

        let rawSlotHeight = availableHeight / CGFloat(barCount)
        let gap = max(0, rawSlotHeight * min(max(style.spacing, 0), 0.9))
        let barHeight = max(1, rawSlotHeight - gap)
        let valueBounds = normalizedValueBounds()
        let lowerWidth = bounds.width * valueBounds.lower
        let upperWidth = bounds.width * valueBounds.upper

        for index in 0..<barCount {
            let volume = workshopBarLevel(index: index, barCount: barCount)
            let width = max(1, lowerWidth + (upperWidth - lowerWidth) * volume)
            let y = verticalInset + CGFloat(index) * rawSlotHeight + gap / 2
            switch mode {
            case .left:
                fillRect(NSRect(x: 0, y: y, width: width, height: barHeight), color: color)
            case .right:
                fillRect(NSRect(x: bounds.width - width, y: y, width: width, height: barHeight), color: color)
            case .center:
                fillRect(NSRect(x: (bounds.width - width) / 2, y: y, width: width, height: barHeight), color: color)
            case .stereo:
                let halfWidth = max(1, width / 2)
                let centerX = bounds.midX
                fillRect(NSRect(x: centerX, y: y, width: halfWidth, height: barHeight), color: color)
                fillRect(NSRect(x: centerX - halfWidth, y: y, width: halfWidth, height: barHeight), color: color)
            }
        }
    }

    private func drawRadialWorkshopBars(
        barCount: Int,
        color: NSColor,
        mode: RadialWorkshopBarMode
    ) {
        let diameter = min(bounds.width, bounds.height)
        guard diameter > 0 else {
            return
        }

        let valueBounds = normalizedValueBounds()
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let baseRadius = diameter * (0.18 + valueBounds.lower * 0.32)
        let maxLength = max(2, diameter * max(valueBounds.upper - valueBounds.lower, 0.04))
        let angleRange = normalizedAngleRange()
        let lineWidth = max(1, min(10, diameter * 0.004 * (1.2 - min(max(style.spacing, 0), 0.9))))

        color.setStroke()
        for index in 0..<barCount {
            let volume = workshopBarLevel(index: index, barCount: barCount)
            let length = max(2, maxLength * volume)
            let angleDegrees = angleRange.start + (CGFloat(index) + 0.5) * angleRange.span / CGFloat(barCount)
            let radians = angleDegrees * .pi / 180

            let innerRadius: CGFloat
            let outerRadius: CGFloat
            switch mode {
            case .inner:
                outerRadius = baseRadius + maxLength
                innerRadius = max(0, outerRadius - length)
            case .outer:
                innerRadius = baseRadius
                outerRadius = baseRadius + length
            }

            let start = NSPoint(
                x: center.x + cos(radians) * innerRadius,
                y: center.y + sin(radians) * innerRadius
            )
            let end = NSPoint(
                x: center.x + cos(radians) * outerRadius,
                y: center.y + sin(radians) * outerRadius
            )
            strokeLine(from: start, to: end, color: color, lineWidth: lineWidth)
        }
    }

    private func normalizedValueBounds() -> (lower: CGFloat, upper: CGFloat) {
        let lower = min(max(style.lowerBound, 0), 1)
        let upper = min(max(style.upperBound, lower), 1)
        return (lower, upper)
    }

    private func normalizedAngleRange() -> (start: CGFloat, span: CGFloat) {
        let start = style.angleStart.isFinite ? style.angleStart : 0
        var end = style.angleEnd.isFinite ? style.angleEnd : 360
        while end <= start {
            end += 360
        }
        return (start, max(1, end - start))
    }

    private func workshopBarLevel(index: Int, barCount: Int) -> CGFloat {
        let frequency = CGFloat(index) / CGFloat(max(1, barCount - 1))
        let lowFrequencyBias = 1.05 - frequency * 0.55
        let wave = 0.76 + 0.24 * sin(CGFloat(index) * 0.57 + smoothedLevel * 10.5)
        let seed = barSeed(index)
        return min(max(smoothedLevel * lowFrequencyBias * wave * seed, 0), 1)
    }

    private func fillRect(_ rect: NSRect, color: NSColor) {
        guard rect.width > 0, rect.height > 0 else {
            return
        }
        color.setFill()
        NSBezierPath(rect: rect).fill()
    }

    private func strokeLine(from start: NSPoint, to end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private func barSeed(_ index: Int) -> CGFloat {
        let bucket = CGFloat((index * 37) % 19)
        return 0.68 + (0.32 * bucket / 18)
    }
}
