import SwiftUI

/// Matches the system launch storyboard while account restoration is pending.
/// Readiness owns the handoff; branding never adds a minimum splash duration.
struct StreamifyLaunchScreen<Status: View>: View {
    let isLoading: Bool
    @ViewBuilder let status: () -> Status

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color("LaunchBackground")
                if geometry.size.height < 480 && !isLoading {
                    // Keep recovery actions usable in phone landscape.
                    ScrollView {
                        HStack(spacing: 40) {
                            brand.frame(maxWidth: .infinity)
                            status().frame(maxWidth: 340)
                        }
                        .padding(32)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                } else if isLoading {
                    // The logo itself, rather than the combined logo/wordmark,
                    // stays at screen center, exactly like LaunchScreen.storyboard.
                    brand.offset(y: 21)
                    VStack {
                        Spacer()
                        status().frame(maxWidth: 340)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, geometry.size.height < 480 ? 16 : max(40, geometry.size.height * 0.08))
                } else {
                    ScrollView {
                        VStack(spacing: 32) {
                            brand
                            status().frame(maxWidth: 340)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .foregroundStyle(Color.white.opacity(0.96))
        .accessibilityIdentifier("streamify-launch-screen")
    }

    private var brand: some View {
        VStack(spacing: 20) {
            Image("streamify-logo")
                .resizable().scaledToFit().frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Text("STREAMIFY")
                .font(.system(size: 18, weight: .semibold))
                .tracking(4)
                .frame(height: 22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streamify")
    }
}
