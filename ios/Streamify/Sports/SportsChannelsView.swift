import SwiftUI

private struct SportsChannelProvider: Identifiable {
    let id: String
    let name: String
    let base: String
    let suffix: String
    let initial: String
}

private struct SportsBroadcaster: Identifiable {
    let name: String
    let detail: String
    let access: String
    let address: String
    var id: String { name }
}

struct SportsChannelsView: View {
    @EnvironmentObject private var playback: SportsPlaybackSession
    @State private var numbers: [String: String] = [:]
    private let providers = [
        SportsChannelProvider(id: "ripple", name: "Ripple Plays", base: "https://rippleplays.shop/newhub/stream-", suffix: ".php", initial: "1"),
        SportsChannelProvider(id: "hd", name: "Stream HD 24/7", base: "https://shd247.xyz/source", suffix: ".html", initial: "020"),
        SportsChannelProvider(id: "center", name: "Streams Center", base: "https://streams.center/embed/ch", suffix: ".php", initial: "50"),
        SportsChannelProvider(id: "pro", name: "Pro Streams", base: "https://prostreams.shop/now/stream-", suffix: ".php", initial: "3")
    ]
    private let broadcasters = [
        SportsBroadcaster(name: "Red Bull TV", detail: "Action sports, live events & replays", access: "Free", address: "https://www.redbull.tv/en_US"),
        SportsBroadcaster(name: "CBS Sports HQ", detail: "24/7 sports news, highlights & analysis", access: "Free", address: "https://www.cbssports.com/watch/live"),
        SportsBroadcaster(name: "CBS Sports Golazo", detail: "Soccer matches, news & highlights", access: "Free", address: "https://www.cbssports.com/watch/cbs-sports-golazo-network"),
        SportsBroadcaster(name: "ESPN", detail: "Live sports & ESPN networks", access: "Subscription / TV provider", address: "https://www.espn.com/watch/"),
        SportsBroadcaster(name: "FOX Sports", detail: "Live events & sports coverage", access: "Subscription / TV provider", address: "https://www.foxsports.com/live"),
        SportsBroadcaster(name: "FS1", detail: "Live games & studio shows", access: "Subscription / TV provider", address: "https://www.foxsports.com/live/fs1"),
        SportsBroadcaster(name: "FS2", detail: "More live sports", access: "Subscription / TV provider", address: "https://www.foxsports.com/live/fs2")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sports channels").font(.title2.bold())
            Text("Stream providers").font(.headline)
            ForEach(providers) { provider in
                SportsPanel {
                    Text(provider.name).font(.headline)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 12) {
                            channelField(provider)
                            watchButton(provider)
                        }
                        VStack(alignment: .leading, spacing: 12) { channelField(provider); watchButton(provider) }
                    }
                }
            }
            Text("Broadcasters").font(.title3.bold())
            Text("Opens the broadcaster site. Availability varies by region.").font(.caption).foregroundStyle(AppTheme.muted)
            ForEach(broadcasters) { broadcaster in
                if let url = sportsHTTPSURL(broadcaster.address) {
                    Link(destination: url) {
                        SportsPanel {
                            HStack { Text(broadcaster.name).font(.headline); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(AppTheme.foreground) }
                            Text(broadcaster.detail).font(.subheadline).foregroundStyle(AppTheme.muted)
                            Text(broadcaster.access).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.horizontal, 20).foregroundStyle(AppTheme.foreground)
    }

    private func channelField(_ provider: SportsChannelProvider) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Channel").font(.caption).foregroundStyle(AppTheme.muted)
            TextField(provider.initial, text: Binding(get: { numbers[provider.id] ?? provider.initial }, set: { numbers[provider.id] = String($0.filter(\.isNumber).prefix(5)) }))
                .keyboardType(.numberPad).font(.subheadline).padding(.horizontal, 14).frame(minHeight: 48)
                .streamifyControlSurface().accessibilityLabel("\(provider.name) channel number")
        }
    }

    private func watchButton(_ provider: SportsChannelProvider) -> some View {
        Button {
            let channel = numbers[provider.id] ?? provider.initial
            if let url = sportsHTTPSURL(provider.base + channel + provider.suffix) { playback.play(title: "\(provider.name) · Channel \(channel)", url: url) }
        } label: {
            Label("Watch", systemImage: "play.fill").font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18).frame(minHeight: 48).foregroundStyle(Color.black)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled((numbers[provider.id] ?? provider.initial).isEmpty)
            .opacity((numbers[provider.id] ?? provider.initial).isEmpty ? 0.45 : 1)
    }
}
