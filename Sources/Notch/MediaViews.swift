import SwiftUI
import NotchCore

private struct HiddenScrollIndicator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { configure(view) }
    private func configure(_ view: NSView) {
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
        }
    }
}

/// A small, crisp cover with a restrained artwork-coloured reflection behind it.
struct AlbumCover: View {
    var image: NSImage?
    var size: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Artwork(image: image, size: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.085, style: .continuous)
                    .strokeBorder(.white.opacity(0.13), lineWidth: 0.5)
            }
            .background {
                if let image, !reduceTransparency {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: size, height: size).clipped()
                        .blur(radius: 13).opacity(0.28).offset(y: 5)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct LyricSeekButton: View {
    var line: LyricLine
    var current: Bool
    var enabled: Bool
    var seek: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: seek) {
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(.system(size: 20, weight: current ? .bold : .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(current ? 1 : hovered ? 0.86 : 0.42))
                .tracking(current ? 0.05 : -0.12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2).padding(.horizontal, 8)
                .background(.white.opacity(hovered ? 0.065 : 0), in: .rect(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(SoftButton()).disabled(!enabled)
            .help("Play from \(clockString(line.time))")
            .accessibilityLabel(line.text.isEmpty ? "Instrumental" : line.text)
            .accessibilityHint("Play from \(clockString(line.time))")
            .onHover { hovered = $0 }
    }
}

struct MediaScrubber: View {
    @ObservedObject var service: MusicService
    @ObservedObject var visualizer: AudioVisualizerService
    var tint: Color
    @State private var seek = 0.0
    @State private var seeking = false
    @State private var pendingSeek: Double?
    @State private var seekToken = UUID()
    @State private var scrubberHovered = false
    var body: some View {
        if let track = service.track {
            VStack(spacing: 3) {
                PremiumSlider(value: Binding(get: { seeking ? seek : pendingSeek ?? min(track.duration, max(0, track.position)) }, set: { value in
                    seek = value
                }), range: 0...max(1, track.duration), tint: tint, label: "Playback position",
                   hoverVisualizer: visualizer.isSupported && visualizer.captureEnabled && visualizer.error == nil, controlHeight: 26, visualizerLevels: visualizer.levels,
                   onHoverChanged: { scrubberHovered = $0; visualizer.setActive($0 && track.playing) }, onEditingChanged: { editing in
                    if editing {
                        seekToken = UUID()
                        seek = pendingSeek ?? track.position
                        pendingSeek = nil
                        seeking = true
                    } else {
                        let target = seek
                        let token = UUID()
                        seekToken = token
                        pendingSeek = target
                        seeking = false
                        service.command("seek", position: target)
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2.2))
                            if seekToken == token { pendingSeek = nil }
                        }
                    }
                }).allowsHitTesting(track.duration > 0).opacity(track.duration > 0 ? 1 : 0.35)
                HStack {
                    let shown = seeking ? seek : pendingSeek ?? track.position
                    Text(clockString(shown)); Spacer()
                    if let error = visualizer.error {
                        Image(systemName: "waveform.badge.exclamationmark")
                            .foregroundStyle(.orange.opacity(0.82))
                            .help(error)
                            .accessibilityLabel(error)
                        Spacer()
                    }
                    Text(track.duration > 0 ? "−" + clockString(max(0, track.duration - shown)) : "Live")
                }.font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
            }
            .onNotchChange(of: track.position) {
                if let pendingSeek, abs(track.position - pendingSeek) < 1.5 { self.pendingSeek = nil }
            }
            .onNotchChange(of: track.playing) { visualizer.setActive(scrubberHovered && track.playing) }
            .onNotchChange(of: track.identity) { pendingSeek = nil; seeking = false; seekToken = UUID() }
            .onDisappear { scrubberHovered = false; visualizer.setActive(false) }
        }
    }
}

struct TransportButtons: View {
    @ObservedObject var service: MusicService
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 20 : 26) {
            Button { service.command("previous track") } label: { Image(systemName: "backward.fill").font(.system(size: 18)) }.help("Previous track").accessibilityLabel("Previous track")
            Button { service.command("playpause") } label: {
                Image(systemName: service.track?.playing == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold)).frame(width: compact ? 32 : 42, height: compact ? 32 : 42)
                    .background(.white.opacity(0.13), in: Circle())
            }.help("Play or pause").accessibilityLabel("Play or pause")
            Button { service.command("next track") } label: { Image(systemName: "forward.fill").font(.system(size: 18)) }.help("Next track").accessibilityLabel("Next track")
        }
    }
}

struct LyricsPane: View {
    @ObservedObject var service: MusicService
    @ObservedObject var lyrics: LyricsService
    var tint: Color
    @State private var followPlayback = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var currentLine: Int? { lyrics.lines.last(where: { $0.time <= (service.track?.position ?? 0) })?.id }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                lyricsBackdrop
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                VStack(alignment: .leading, spacing: 0) {
                if !lyrics.lines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(lyrics.lines) { line in
                                    LyricSeekButton(line: line, current: line.id == currentLine,
                                                    enabled: (service.track?.duration ?? 0) > line.time) {
                                        service.command("seek", position: line.time)
                                        followPlayback = true
                                    }.id(line.id)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8).padding(.bottom, 44).padding(.horizontal, 24)
                            .background(HiddenScrollIndicator())
                        }.scrollIndicators(.hidden)
                            .onNotchChange(of: followPlayback) { if followPlayback, let currentLine { proxy.scrollTo(currentLine, anchor: .center) } }
                            .onNotchChange(of: currentLine, initial: true) {
                                if followPlayback, let currentLine { withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo(currentLine, anchor: .center) } }
                            }
                    }
                } else if !lyrics.plain.isEmpty {
                    ScrollView {
                        Text(lyrics.plain)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 44)
                            .background(HiddenScrollIndicator())
                    }.scrollIndicators(.hidden)
                } else {
                    VStack(spacing: 12) {
                        if lyrics.loading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "quote.bubble").font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.3)) }
                        Text(lyrics.loading ? "Finding the words…" : lyrics.status).font(.system(size: 14)).foregroundStyle(.white.opacity(0.5))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                }.padding(.horizontal, 8).padding(.vertical, 8)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5) }
        }
    }

    @ViewBuilder private var lyricsBackdrop: some View {
        if let artwork = service.artwork, !reduceTransparency {
            Image(nsImage: artwork).resizable().scaledToFill()
                .blur(radius: 26).scaleEffect(1.16).saturation(0.82)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.34), .black.opacity(0.72), .black.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .accessibilityHidden(true)
        } else {
            LinearGradient(colors: [Color(white: 0.13), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
