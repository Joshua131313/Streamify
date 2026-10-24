import SwiftUI
import UIKit

/// A public UISlider preserves its actual thumb geometry, native adjustable
/// accessibility and cancellation. Dragging updates preview state; only release
/// (or an accessibility adjustment) commits a playback seek.
@MainActor
struct OfflineSeekSlider: UIViewRepresentable {
    @Binding var value: Double
    let duration: Double
    var enabled = true
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Double) -> Void
    let onThumbMoved: (CGRect) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> OfflineTrackingSlider {
        let slider = OfflineTrackingSlider(frame: .zero)
        slider.minimumTrackTintColor = UIColor(red: 0.9, green: 0.04, blue: 0.08, alpha: 1)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        slider.thumbTintColor = slider.minimumTrackTintColor
        slider.accessibilityIdentifier = "offline-progress"
        slider.accessibilityLabel = "Playback progress"
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.onBegin = { [weak coordinator = context.coordinator] slider in coordinator?.begin(slider) }
        slider.onFinish = { [weak coordinator = context.coordinator] slider, canceled in coordinator?.finish(slider, canceled: canceled) }
        slider.onLayout = { [weak coordinator = context.coordinator] slider in coordinator?.reportThumb(slider) }
        updateUIView(slider, context: context)
        return slider
    }
    func updateUIView(_ slider: OfflineTrackingSlider, context: Context) {
        context.coordinator.parent = self
        slider.minimumValue = 0
        slider.maximumValue = Float(duration.isFinite ? max(1, min(duration, Double(Float.greatestFiniteMagnitude))) : 1)
        slider.isEnabled = enabled && duration.isFinite && duration > 0
        if !slider.isTracking {
            let bounded = value.isFinite ? min(Double(slider.maximumValue), max(0, value)) : 0
            if abs(Double(slider.value) - bounded) > 0.01 { slider.setValue(Float(bounded), animated: false) }
        }
        slider.accessibilityValue = "\(OfflineSeekPreviewMath.timestamp(Double(slider.value))) of \(OfflineSeekPreviewMath.timestamp(duration))"
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: OfflineTrackingSlider, context: Context) -> CGSize? {
        CGSize(width: max(44, proposal.width ?? 200), height: 44)
    }
    static func dismantleUIView(_ slider: OfflineTrackingSlider, coordinator: Coordinator) {
        slider.onBegin = nil; slider.onFinish = nil; slider.onLayout = nil
        slider.removeTarget(coordinator, action: nil, for: .allEvents)
        coordinator.cancel()
    }

    @MainActor final class Coordinator: NSObject {
        var parent: OfflineSeekSlider
        private var editing = false
        private var pendingThumb: CGRect?
        private var lastThumb: CGRect?
        private var thumbTask: Task<Void, Never>?
        init(_ parent: OfflineSeekSlider) { self.parent = parent }
        func begin(_ slider: OfflineTrackingSlider) {
            guard !editing else { return }
            editing = true; lastThumb = nil; parent.onEditingChanged(true)
            // The start callback may set scrubbing state but cannot overwrite the
            // slider's initial touch value with an older player timestamp.
            parent.value = Double(slider.value); reportThumb(slider)
        }
        @objc func changed(_ slider: OfflineTrackingSlider) {
            parent.value = Double(slider.value)
            slider.accessibilityValue = "\(OfflineSeekPreviewMath.timestamp(Double(slider.value))) of \(OfflineSeekPreviewMath.timestamp(parent.duration))"
            if slider.isTracking || editing { reportThumb(slider) }
            else { parent.onCommit(Double(slider.value)) }
        }
        func finish(_ slider: OfflineTrackingSlider, canceled: Bool) {
            guard editing else { return }
            let committed = Double(slider.value)
            parent.value = committed; editing = false
            cancelThumbReport()
            if !canceled { parent.onCommit(committed) }
            parent.onEditingChanged(false)
        }
        func reportThumb(_ slider: OfflineTrackingSlider) {
            guard editing, slider.window != nil else { return }
            let track = slider.trackRect(forBounds: slider.bounds)
            let thumb = slider.thumbRect(forBounds: slider.bounds, trackRect: track, value: slider.value)
            let rect = slider.convert(thumb, to: nil)
            guard rect != lastThumb, rect != pendingThumb else { return }
            pendingThumb = rect
            guard thumbTask == nil else { return }
            thumbTask = Task { @MainActor [weak self, weak slider] in
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.thumbTask = nil
                guard let slider, self.editing, slider.window != nil,
                      let rect = self.pendingThumb else { self.pendingThumb = nil; return }
                self.pendingThumb = nil; self.lastThumb = rect
                // Dispatch after layout/updateUIView; the parent can safely
                // store this anchor in SwiftUI state without a layout loop.
                self.parent.onThumbMoved(rect)
            }
        }
        private func cancelThumbReport() {
            thumbTask?.cancel(); thumbTask = nil; pendingThumb = nil; lastThumb = nil
        }
        func cancel() {
            cancelThumbReport()
            if editing {
                editing = false
                let ended = parent.onEditingChanged
                Task { @MainActor in ended(false) }
            }
        }
    }
}

@MainActor
final class OfflineTrackingSlider: UISlider {
    var onBegin: ((OfflineTrackingSlider) -> Void)?
    var onFinish: ((OfflineTrackingSlider, Bool) -> Void)?
    var onLayout: ((OfflineTrackingSlider) -> Void)?
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        // Mark editing before UISlider can emit an initial valueChanged event;
        // that event must never be mistaken for an accessibility seek commit.
        onBegin?(self)
        let accepted = super.beginTracking(touch, with: event)
        if accepted { onLayout?(self) }
        else { onFinish?(self, true) }
        return accepted
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event); onFinish?(self, false)
    }
    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event); onFinish?(self, true)
    }
    override func layoutSubviews() { super.layoutSubviews(); onLayout?(self) }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: 0, dy: -max(0, (44 - bounds.height) / 2)).contains(point)
    }
}
