import SwiftUI

/// Android's download ring: 2pt stroke, quiet track and the actual byte fraction.
/// The parent owns its action and status label; this ring is decorative.
struct DownloadActivityIndicator: View {
    let progress: Double?
    let size: CGFloat
    var tint: Color = AppTheme.foreground
    /// The toolbar remains visibly active even when a known fraction is steady.
    /// Rows can disable this while still animating indeterminate transfers.
    var animated = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private var fraction: Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(1, max(0, progress))
    }
    private var rotates: Bool {
        scenePhase == .active && !reduceMotion && !voiceOver && (animated || fraction == nil)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !rotates)) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            let angle = rotates ? cycle * 360 : 0
            ZStack {
                Circle().stroke(tint.opacity(0.22), lineWidth: 2)
                Circle().trim(from: 0, to: fraction ?? 0.24)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90 + angle))
                    .animation(reduceMotion || voiceOver ? nil : .easeOut(duration: 0.25), value: fraction)
            }
            .opacity(rotates && animated ? 0.8 + 0.2 * cos(cycle * .pi * 2) : 1)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
