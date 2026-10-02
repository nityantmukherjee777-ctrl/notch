import SwiftUI
import NotchCore

struct NotchIconButton: View {
    let symbol: String
    let title: String
    var selected = false
    var action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(selected ? 1 : hovered ? 0.95 : 0.52))
                .frame(width: 28, height: 28)
                .background(.white.opacity(selected ? 0.14 : hovered ? 0.08 : 0), in: Circle())
                .contentShape(Circle())
        }.buttonStyle(SoftButton()).help(title).accessibilityLabel(title)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}

struct NotchToolbar: View {
    @ObservedObject var state: AppState
    var safeTop: CGFloat
    var notchWidth: CGFloat
    var select: (ActivityID) -> Void
    var back: () -> Void
    var close: () -> Void
    var body: some View {
        Group {
            if state.mediaDetail {
                HStack {
                    NotchIconButton(symbol: "arrow.left", title: "Back to player", selected: true, action: back)
                        .overlay { Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.6).padding(1).allowsHitTesting(false) }
                    Spacer()
                }
            } else {
                HStack(spacing: 0) {
                    HStack(spacing: 1) {
                        ForEach(state.enabledActivities) { activity in
                            NotchIconButton(symbol: activity.symbol, title: activity.title, selected: state.selected == activity) { select(activity) }
                        }
                    }
                    Spacer(minLength: safeTop > 0 ? notchWidth + 4 : 16)
                    HStack(spacing: 1) {
                        NotchIconButton(symbol: "gearshape", title: "Settings") { state.openSettings?() }
                        NotchIconButton(symbol: "chevron.up", title: "Collapse · Escape", action: close)
                    }
                }
            }
        }.frame(maxWidth: .infinity).padding(.top, 3)
    }
}

struct MediaSources: View {
    @ObservedObject var service: MusicService
    var body: some View {
        HStack(spacing: 4) {
            NotchIconButton(symbol: "sparkles", title: "Automatically choose playing media", selected: service.preferredSource == nil) { service.preferredSource = nil }
            ForEach(service.availableTracks, id: \.source) { track in
                NotchIconButton(symbol: track.source == .spotify ? "s.circle" : track.source == .appleMusic ? "music.note" : "globe",
                                title: "\(track.sourceName) · \(track.title)", selected: service.preferredSource == track.source) { service.preferredSource = track.source }
            }
        }
    }
}

struct PremiumPlayer: View {
    @ObservedObject var service: MusicService
    @ObservedObject var visualizer: AudioVisualizerService
    var showLyrics: () -> Void
    var body: some View {
        if let track = service.track {
            HStack(alignment: .center, spacing: 20) {
                Button(action: showLyrics) {
                    AlbumCover(image: service.artwork, size: 112)
                }.help("Show lyrics").accessibilityLabel("Show lyrics")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.title).font(.system(size: 16, weight: .semibold)).lineLimit(1).help(track.title)
                            Text(track.artist.isEmpty ? track.sourceName : track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                            if !track.album.isEmpty && track.album != track.title {
                                Text(track.album).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 2) {
                            MediaSources(service: service)
                            NotchIconButton(symbol: "arrow.up.forward.app", title: "Open media app") {
                                service.openSourceApp()
                            }
                        }
                    }
                    MediaScrubber(service: service, visualizer: visualizer, tint: .white.opacity(0.88))
                    HStack {
                        NotchIconButton(symbol: "gobackward.15", title: "Back 15 seconds") { service.seekRelative(-15) }.disabled(track.duration <= 0)
                        Spacer(minLength: 0)
                        TransportButtons(service: service, compact: true)
                        Spacer(minLength: 0)
                        NotchIconButton(symbol: "goforward.15", title: "Forward 15 seconds") { service.seekRelative(15) }.disabled(track.duration <= 0)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 14) {
                EmptyFeature(symbol: "music.note", title: "Nothing playing", detail: "Your music and video will appear here.")
                HStack(spacing: 18) {
                    NotchIconButton(symbol: "s.circle", title: "Connect Spotify") { service.connect(.spotify) }
                    NotchIconButton(symbol: "music.note", title: "Connect Apple Music") { service.connect(.appleMusic) }
                }
            }.padding(.vertical, 15)
        }
    }
}
