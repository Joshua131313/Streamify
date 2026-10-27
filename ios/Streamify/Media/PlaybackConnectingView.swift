import SwiftUI

/// Indeterminate connection status, without a percentage or a modal backdrop.
struct PlaybackConnectingView: View {
    let title: String
    var subtitle: String? = nil
    var game: SportsGame? = nil
    var compact = false
    var onVideo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    private var ink: Color { onVideo ? .white : AppTheme.foreground }

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 12) { dots; Text(title).font(.subheadline.weight(.medium)) }
            } else {
                VStack(spacing: 16) {
                    if let game {
                        HStack(spacing: 18) {
                            RemoteArtwork(url: game.away.logoURL, contentMode: .fit).frame(width: 36, height: 36)
                            Text("vs").font(.caption).foregroundStyle(ink.opacity(0.45))
                            RemoteArtwork(url: game.home.logoURL, contentMode: .fit).frame(width: 36, height: 36)
                        }.accessibilityHidden(true)
                    }
                    VStack(spacing: 6) {
                        Text(title).font(.subheadline.weight(.medium))
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(.caption).foregroundStyle(ink.opacity(0.55)).lineLimit(2)
                        }
                    }.multilineTextAlignment(.center)
                    dots
                }.padding(24)
            }
        }
        .foregroundStyle(ink)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
        .onAppear { pulsing = !reduceMotion }
        .onChange(of: reduceMotion) { _, reduced in pulsing = !reduced }
    }
    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle().fill(ink).frame(width: 5, height: 5)
                    .opacity(reduceMotion ? 0.6 : pulsing ? 0.9 : 0.25)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.65).repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.13), value: pulsing)
            }
        }.frame(height: 12).accessibilityHidden(true)
    }
}
