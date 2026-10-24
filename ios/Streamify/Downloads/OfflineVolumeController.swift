import SwiftUI
import MediaPlayer
import Combine

/// Reads and adjusts the system control mounted by the offline player.
/// No volume is cached: hardware-button changes remain the source of truth.
@MainActor
final class OfflineVolumeController: ObservableObject {
    private weak var volumeView: MPVolumeView?

    func volume() -> Double? {
        guard let slider = mountedSlider() else { return nil }
        return normalizedValue(of: slider)
    }

    @discardableResult
    func setVolume(_ value: Double) -> Double? {
        guard value.isFinite, let slider = mountedSlider() else { return nil }
        let bounded = min(1, max(0, value))
        let lower = Double(slider.minimumValue)
        let upper = Double(slider.maximumValue)
        slider.setValue(Float(lower + bounded * (upper - lower)), animated: false)
        slider.sendActions(for: .valueChanged)
        return normalizedValue(of: slider)
    }

    fileprivate func attach(_ view: MPVolumeView) {
        guard volumeView !== view else { return }
        volumeView = view
    }

    fileprivate func detach(_ view: MPVolumeView) {
        guard volumeView === view else { return }
        volumeView = nil
    }

    private func mountedSlider() -> UISlider? {
        guard let view = volumeView, view.window != nil,
              view.showsVolumeSlider,
              let slider = findSlider(in: view),
              slider.isEnabled, !slider.isHidden,
              slider.minimumValue.isFinite, slider.maximumValue.isFinite,
              slider.maximumValue > slider.minimumValue,
              slider.value.isFinite else { return nil }
        return slider
    }

    private func findSlider(in view: UIView) -> UISlider? {
        for child in view.subviews {
            if let slider = child as? UISlider { return slider }
            if let slider = findSlider(in: child) { return slider }
        }
        return nil
    }

    private func normalizedValue(of slider: UISlider) -> Double? {
        let lower = Double(slider.minimumValue)
        let upper = Double(slider.maximumValue)
        let value = Double(slider.value)
        guard lower.isFinite, upper.isFinite, value.isFinite, upper > lower else { return nil }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }
}

@MainActor
struct OfflineSystemVolume: UIViewRepresentable {
    let controller: OfflineVolumeController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        view.showsRouteButton = false
        view.tintColor = .white
        view.accessibilityIdentifier = "offline-system-volume"
        context.coordinator.bind(controller: controller, view: view)
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        context.coordinator.bind(controller: controller, view: view)
    }

    static func dismantleUIView(_ view: MPVolumeView, coordinator: Coordinator) {
        coordinator.detach(view)
    }

    @MainActor
    final class Coordinator {
        private weak var controller: OfflineVolumeController?
        private weak var view: MPVolumeView?

        fileprivate func bind(controller: OfflineVolumeController, view: MPVolumeView) {
            guard self.controller !== controller || self.view !== view else { return }
            if let previousView = self.view { self.controller?.detach(previousView) }
            self.controller = controller
            self.view = view
            controller.attach(view)
        }

        fileprivate func detach(_ view: MPVolumeView) {
            guard self.view === view else { return }
            controller?.detach(view)
            controller = nil
            self.view = nil
        }
    }
}
