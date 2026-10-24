import SwiftUI
import UIKit

/// Mirrors Android HoldUnlockView: a one-second ring followed by the 280ms
/// opening shackle. UIButton owns tracking so a short release cannot unlock.
@MainActor
struct OfflineHoldUnlockControl: UIViewRepresentable {
    let reduceMotion: Bool
    let onHold: () -> Void
    let onCancel: () -> Void
    let onUnlock: () -> Void

    func makeUIView(context: Context) -> OfflineHoldUnlockButton {
        let button = OfflineHoldUnlockButton(frame: .zero)
        updateUIView(button, context: context)
        return button
    }

    func updateUIView(_ button: OfflineHoldUnlockButton, context: Context) {
        button.reduceMotion = reduceMotion
        button.onHold = onHold; button.onCancel = onCancel; button.onUnlock = onUnlock
    }

    static func dismantleUIView(_ button: OfflineHoldUnlockButton, coordinator: ()) {
        button.reset(notify: false)
        button.onHold = nil; button.onCancel = nil; button.onUnlock = nil
    }
}

@MainActor
final class OfflineHoldUnlockButton: UIButton {
    var reduceMotion = false
    var onHold: (() -> Void)?
    var onCancel: (() -> Void)?
    var onUnlock: (() -> Void)?
    private var displayLink: CADisplayLink?
    private var startedAt: CFTimeInterval = 0
    private var progress: CGFloat = 0
    private var opening: CGFloat = 0
    private var completing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "offline-unlock"
        accessibilityLabel = "Unlock screen"
        accessibilityHint = "Touch and hold for one second to unlock playback controls"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard !completing, displayLink == nil else { return false }
        _ = super.beginTracking(touch, with: event)
        progress = 0; opening = 0; startedAt = CACurrentMediaTime()
        onHold?()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
        setNeedsDisplay()
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !completing, !bounds.contains(touch.location(in: self)) {
            reset(notify: true)
            return false
        }
        return super.continueTracking(touch, with: event)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if !completing { reset(notify: true) }
        super.endTracking(touch, with: event)
    }

    override func cancelTracking(with event: UIEvent?) {
        if !completing { reset(notify: true) }
        super.cancelTracking(with: event)
    }

    override func accessibilityActivate() -> Bool {
        // VoiceOver activates this native button directly, without requiring a
        // gesture that conflicts with VoiceOver's own touch-and-hold actions.
        reset(notify: false)
        onHold?(); onUnlock?()
        return true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { reset(notify: false) }
    }

    func reset(notify: Bool) {
        let wasHolding = displayLink != nil
        displayLink?.invalidate(); displayLink = nil
        progress = 0; opening = 0; completing = false
        setNeedsDisplay()
        if notify, wasHolding { onCancel?() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard window != nil else { reset(notify: false); return }
        let elapsed = max(0, link.timestamp - startedAt)
        progress = CGFloat(min(1, elapsed))
        if elapsed >= 1 {
            completing = true
            let fraction = min(1, (elapsed - 1) / 0.28)
            opening = CGFloat((1 - cos(.pi * fraction)) / 2)
            if fraction >= 1 {
                displayLink?.invalidate(); displayLink = nil
                setNeedsDisplay()
                onUnlock?()
                return
            }
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let x = bounds.midX, y: CGFloat = 34
        context.setLineWidth(2); context.setLineCap(.round); context.setLineJoin(.round)
        context.setStrokeColor(UIColor.white.withAlphaComponent(55.0 / 255).cgColor)
        context.strokeEllipse(in: CGRect(x: x - 29, y: y - 29, width: 58, height: 58))
        context.setStrokeColor(UIColor.white.cgColor)
        if progress > 0 {
            context.addArc(center: CGPoint(x: x, y: y), radius: 29,
                startAngle: -.pi / 2, endAngle: -.pi / 2 + .pi * 2 * progress, clockwise: false)
            context.strokePath()
        }
        let body = UIBezierPath(roundedRect: CGRect(x: x - 10, y: y - 1, width: 20, height: 16), cornerRadius: 2)
        context.addPath(body.cgPath); context.strokePath()
        context.saveGState()
        context.translateBy(x: x + 7, y: y - 1)
        if !reduceMotion { context.rotate(by: -32 * .pi / 180 * opening) }
        context.translateBy(x: -x - 7, y: -y + 1)
        context.move(to: CGPoint(x: x - 7, y: y - 1))
        context.addLine(to: CGPoint(x: x - 7, y: y - 9))
        context.addCurve(to: CGPoint(x: x + 7, y: y - 9),
            control1: CGPoint(x: x - 7, y: y - 20), control2: CGPoint(x: x + 7, y: y - 20))
        context.addLine(to: CGPoint(x: x + 7, y: y - 1)); context.strokePath()
        context.restoreGState()
        context.move(to: CGPoint(x: x, y: y + 5)); context.addLine(to: CGPoint(x: x, y: y + 9)); context.strokePath()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let label = completing ? "Unlocking" : "Hold to unlock"
        (label as NSString).draw(in: CGRect(x: 0, y: 70, width: bounds.width, height: 20),
            withAttributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
    }
}
