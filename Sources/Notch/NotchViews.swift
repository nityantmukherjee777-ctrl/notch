import SwiftUI
import NotchCore

extension AppState {
    var tint: Color {
        switch preferences.accent {
        case "blue": return .blue
        case "mint": return Color(red: 0.64, green: 0.91, blue: 0.77)
        case "peach": return Color(red: 1, green: 0.7, blue: 0.47)
        default: return .white.opacity(0.92)
        }
    }
}

struct SoftButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct NotchSurface: Shape {
    var floating = false
    func path(in r: CGRect) -> Path {
        if floating { return RoundedRectangle(cornerRadius: min(26, r.height / 2), style: .continuous).path(in: r) }
        let shoulder = min(12.0, r.height * 0.24)
        let radius = min(26.0, r.height * 0.42)
        let left = r.minX + shoulder, right = r.maxX - shoulder
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addCurve(to: CGPoint(x: left, y: r.minY + shoulder),
                      control1: CGPoint(x: left, y: r.minY), control2: CGPoint(x: left, y: r.minY + shoulder * 0.35))
        path.addLine(to: CGPoint(x: left, y: r.maxY - radius))
        path.addCurve(to: CGPoint(x: left + radius, y: r.maxY),
                      control1: CGPoint(x: left, y: r.maxY - radius * 0.35), control2: CGPoint(x: left + radius * 0.35, y: r.maxY))
        path.addLine(to: CGPoint(x: right - radius, y: r.maxY))
        path.addCurve(to: CGPoint(x: right, y: r.maxY - radius),
                      control1: CGPoint(x: right - radius * 0.35, y: r.maxY), control2: CGPoint(x: right, y: r.maxY - radius * 0.35))
        path.addLine(to: CGPoint(x: right, y: r.minY + shoulder))
        path.addCurve(to: CGPoint(x: r.maxX, y: r.minY),
                      control1: CGPoint(x: right, y: r.minY + shoulder * 0.35), control2: CGPoint(x: right, y: r.minY))
        path.closeSubpath()
        return path
    }
}

struct NotchRoot: View {
    @ObservedObject var state: AppState
    var safeTop: CGFloat
    var notchWidth: CGFloat
    var expandedWidth: CGFloat
    var open: (ActivityID?, Bool) -> Void
    var showLyrics: () -> Void
    var back: () -> Void
    var close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Namespace private var selection
    var body: some View {
        ZStack(alignment: .top) {
            NotchSurface(floating: safeTop == 0).fill(.black)
                .frame(width: state.surfaceSize.width, height: state.surfaceSize.height)
            ZStack(alignment: .top) {
                if state.presentingExpanded {
                    VStack(spacing: 0) {
                        NotchToolbar(state: state, safeTop: safeTop, notchWidth: notchWidth,
                                     select: { open($0, true) }, back: back, close: close)
                            .frame(height: max(safeTop, 28) + 8)
                        Group {
                            switch state.selected {
                            case .music:
                                if state.mediaDetail {
                                    LyricsPane(service: state.music, lyrics: state.lyrics, tint: state.tint)
                                } else {
                                    PremiumPlayer(service: state.music, visualizer: state.visualizer, showLyrics: showLyrics)
                                }
                            case .timer: TimerPane(service: state.timer, tint: state.tint)
                            case .power: PowerPane(service: state.power, tint: state.tint)
                            case .codex: CodexPane(service: state.codex, tint: state.tint)
                            }
                        }.frame(height: state.mediaDetail ? 364 : 142).clipped().padding(.top, 8).padding(.bottom, 8)
                        if !state.mediaDetail {
                            if let hud = state.hud, state.hardwareHUD {
                                ExpandedHUDView(reading: hud).frame(height: 24).padding(.top, 4)
                            } else {
                                footer
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(width: contentWidth)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.28, extraBounce: 0), value: state.mediaDetail)
                    .transition(.opacity)
                } else if let hud = state.hud {
                    HUDView(reading: hud, notchWidth: notchWidth)
                        .frame(width: notchWidth + 230, height: NotchGeometry.compactHeight(safeTop: safeTop))
                } else if let device = state.bluetooth.announcement {
                    Button { open(nil, true) } label: {
                        BluetoothConnectionIndicator(device: device, notchWidth: notchWidth,
                            wingWidth: (114 * state.preferences.compactScale - 16) / 2,
                            height: NotchGeometry.compactHeight(safeTop: safeTop))
                            .id(device.id)
                    }.help("\(device.statusDescription) · open NotchHarbor")
                        .transition(.opacity)
                } else {
                    compact.frame(width: compactWidth).transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: state.presentingExpanded)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: state.bluetooth.announcement?.id)
            .frame(width: expandedWidth, height: 440, alignment: .top)
            .mask(alignment: .top) {
                NotchSurface(floating: safeTop == 0)
                    .frame(width: state.surfaceSize.width, height: state.surfaceSize.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white).tint(state.tint).preferredColorScheme(.dark).buttonStyle(SoftButton())
        .onNotchChange(of: state.music.track?.identity) {
            if state.mediaDetail { state.lyrics.load(state.music.track) }
        }
    }
    private var contentWidth: CGFloat {
        return NotchGeometry.expandedSize(availableWidth: expandedWidth - 32, safeTop: safeTop,
                                          lyrics: state.mediaDetail).width
    }
    private var compactWidth: CGFloat {
        notchWidth + (state.primary != nil ? 114 * state.preferences.compactScale : (safeTop == 0 ? 16 : 0)) + (state.power.isAwake ? 60 : 0)
    }
    private var compact: some View {
        HStack(spacing: 0) {
            if state.power.isAwake { Color.clear.frame(width: 30) }
            if let primary = state.primary {
                Button { open(primary, true) } label: {
                    HStack(spacing: 0) {
                        compactLeading(primary).frame(width: (114 * state.preferences.compactScale - 16) / 2)
                        Color.clear.frame(width: notchWidth)
                        compactTrailing(primary).frame(width: (114 * state.preferences.compactScale - 16) / 2)
                    }.frame(maxHeight: .infinity)
                }.help("Open \(primary.title)")
            } else {
                Button { open(nil, true) } label: {
                    HStack {
                        if safeTop == 0 { Image(systemName: "circle.lefthalf.filled"); Text("NotchHarbor").font(.system(size: 12, weight: .medium)) }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.help("Open NotchHarbor")
            }
            if state.power.isAwake {
                Button { state.power.stop() } label: { Image(systemName: "cup.and.saucer.fill").font(.system(size: 12)).foregroundStyle(state.tint).frame(width: 30, height: 30) }
                    .help("Keep Awake is on. Click to turn off.")
            }
        }.padding(.horizontal, 8).frame(height: NotchGeometry.compactHeight(safeTop: safeTop))
    }
    @ViewBuilder private func compactLeading(_ activity: ActivityID) -> some View {
        if activity == .music { Artwork(image: state.music.artwork, size: 22) }
        else { Image(systemName: activity.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(state.tint) }
    }
    @ViewBuilder private func compactTrailing(_ activity: ActivityID) -> some View {
        switch activity {
        case .music:
            AudioPlaybackBars(visualizer: state.visualizer, playing: state.music.track?.playing == true,
                              color: state.music.artworkAccent)
                .frame(width: 23, height: 19).allowsHitTesting(false).accessibilityHidden(true)
        case .timer: Text(clockString(state.timer.remaining)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(state.tint)
        case .codex: QuotaCompact(service: state.codex, tint: state.tint)
        case .power: Text("On").font(.caption)
        }
    }
    private var footer: some View {
        HStack(spacing: 14) {
            if state.preferences.powerEnabled {
                Button { state.power.toggle() } label: {
                    Image(systemName: "cup.and.saucer\(state.power.isAwake ? ".fill" : "")")
                        .font(.system(size: 15)).foregroundStyle(state.power.isAwake ? state.tint : .white.opacity(0.5))
                }.help(state.power.isAwake ? "Turn off Keep Awake" : "Keep this Mac awake")
                    .contextMenu {
                        Button("Until I turn it off") { state.power.start(minutes: 0) }
                        ForEach([30, 60, 120], id: \.self) { minutes in Button("\(minutes) minutes") { state.power.start(minutes: minutes) } }
                        if state.power.isAwake { Button("Turn off") { state.power.stop() } }
                    }
            }
            if state.preferences.volumeEnabled { VolumeControl(service: state.audio).frame(maxWidth: 150) }
            if let brightness = state.brightness.value {
                HStack(spacing: 5) {
                    Image(systemName: "sun.max.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    PremiumSlider(value: Binding(get: { Double(state.brightness.value ?? brightness) }, set: { state.brightness.set(Float($0)) }), range: 0.05...1, tint: state.tint, label: "Display brightness")
                }.frame(maxWidth: 95)
            }
            Spacer(minLength: 0)
            if state.preferences.batteryEnabled, let percentage = state.battery.percent {
                HStack(spacing: 5) {
                    Text("\(percentage)%").font(.system(size: 11, weight: .medium, design: .rounded))
                    Image(systemName: state.battery.pluggedIn ? "battery.100percent.bolt" : "battery.\(percentage > 75 ? 100 : percentage > 50 ? 75 : percentage > 25 ? 50 : percentage > 10 ? 25 : 0)percent")
                }.foregroundStyle(state.battery.charging ? state.tint : .white.opacity(0.5))
                    .help(state.battery.pluggedIn ? "Connected to power" : "On battery")
            }
        }.frame(height: 24).padding(.top, 4)
    }
}

struct Artwork: View {
    var image: NSImage?
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.085).fill(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "music.note").font(.system(size: size * 0.31, weight: .light)).foregroundStyle(.white.opacity(0.4)) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.085))
    }
}

struct EmptyFeature: View {
    var symbol: String; var title: String; var detail: String; var action: String? = nil; var perform: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.white.opacity(0.35))
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let action { Button(action) { perform?() }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8).background(.white.opacity(0.1), in: Capsule()) }
        }
        .frame(width: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TimerPane: View {
    @ObservedObject var service: TimerService
    var tint: Color
    @State private var name = "Focus"
    @State private var minutes = "25"
    var body: some View {
        VStack(spacing: 10) {
            if service.countdown.isActive {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.countdown.name.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(tint)
                        Text(clockString(service.remaining)).font(.system(size: 42, weight: .light, design: .rounded)).monospacedDigit()
                    }
                    Color.clear.frame(width: 26)
                    HStack(spacing: 8) {
                        if service.countdown.completed {
                            action("Done") { service.reset() }
                        } else {
                            action(service.countdown.isPaused ? "Resume" : "Pause") { service.togglePause() }
                            Button("Cancel") { service.reset() }
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.52))
                                .padding(.horizontal, 10).padding(.vertical, 8)
                        }
                    }
                }
                GeometryReader { proxy in
                    Capsule().fill(.white.opacity(0.1)).overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, service.remaining / max(1, service.countdown.duration))))
                    }
                }.frame(height: 3)
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("FOCUS TIMER").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.38))
                        TextField("Timer name", text: $name).textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .semibold)).accessibilityLabel("Timer name")
                    }
                    .frame(width: 124, alignment: .leading)
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 40)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        TextField("25", text: $minutes).textFieldStyle(.plain)
                            .font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit()
                            .multilineTextAlignment(.trailing).frame(width: 66).accessibilityLabel("Duration in minutes")
                        Text("min").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.38))
                        action("Start", disabled: !validDuration) { service.start(name: name, minutes: Double(minutes) ?? 25) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 0.5) }
                HStack(spacing: 11) {
                    ForEach([5, 15, 25, 45, 60], id: \.self) { value in
                        let selected = Int(minutes) == value
                        Button("\(value)m") { minutes = String(value) }
                            .font(.system(size: 10, weight: selected ? .semibold : .medium))
                            .foregroundStyle(.white.opacity(selected ? 0.95 : 0.5))
                            .frame(width: 68).padding(.vertical, 8)
                            .background(.white.opacity(selected ? 0.14 : 0.055), in: Capsule())
                            .overlay { Capsule().strokeBorder(.white.opacity(selected ? 0.13 : 0.04), lineWidth: 0.5) }
                    }
                }
                if !validDuration { Text("Enter 1–1,440 minutes.").font(.system(size: 9)).foregroundStyle(.orange.opacity(0.8)) }
            }
        }
        .frame(width: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var validDuration: Bool { guard let value = Double(minutes), value.isFinite else { return false }; return value >= 1 && value <= 1440 }
    private func action(_ title: String, disabled: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 18).padding(.vertical, 8).foregroundStyle(.black).background(tint.opacity(disabled ? 0.3 : 1), in: Capsule()).fixedSize().disabled(disabled)
    }
}

struct PowerPane: View {
    @ObservedObject var service: PowerService
    var tint: Color
    @State private var minutes = 0
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: service.isAwake ? "cup.and.saucer.fill" : "cup.and.saucer").font(.system(size: 27, weight: .light)).foregroundStyle(service.isAwake ? tint : .white.opacity(0.45))
            Text(service.isAwake ? "Keeping your Mac awake" : "Keep Awake").font(.system(size: 18, weight: .medium))
            Text(service.until.map { "Awake until \($0.formatted(date: .omitted, time: .shortened))" } ?? (service.isAwake ? "Your Mac stays awake until you turn this off." : "Keep your Mac and display awake while you work."))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 16) {
                if !service.isAwake {
                    Picker("Duration", selection: $minutes) { Text("Until turned off").tag(0); Text("30 minutes").tag(30); Text("1 hour").tag(60); Text("2 hours").tag(120) }.labelsHidden().frame(width: 155)
                }
                Button(service.isAwake ? "Turn off" : "Keep awake") { service.toggle(minutes: minutes) }
                    .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 18).padding(.vertical, 8).foregroundStyle(.black).background(tint, in: Capsule())
            }
            if let error = service.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VolumeControl: View {
    @ObservedObject var service: AudioService
    var body: some View {
        HStack(spacing: 8) {
            Button { service.toggleMute() } label: { Image(systemName: service.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 11)) }
                .disabled(!service.canMute).help(service.canMute ? "Mute \(service.deviceName)" : "This output has no mute control")
            if service.canSetVolume {
                PremiumSlider(value: Binding(get: { Double(service.volume) }, set: { service.setVolume(Float($0)) }), tint: .white.opacity(0.92), label: "Output volume").help(service.deviceName)
            } else { Text("Device volume").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).help("Adjust volume on \(service.deviceName)") }
        }.foregroundStyle(.white.opacity(0.5))
    }
}

struct QuotaCompact: View {
    @ObservedObject var service: CodexService
    var tint: Color
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            if let snapshot = service.snapshot, let window = snapshot.primary ?? snapshot.secondary, !snapshot.isStale(at: timeline.date) {
                Text("\(window.remainingPercent)%").foregroundStyle(window.remainingPercent <= 10 ? .orange : tint)
            } else { Text("—").foregroundStyle(.white.opacity(0.5)) }
        }.font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
    }
}

struct CodexPane: View {
    @ObservedObject var service: CodexService
    var tint: Color
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            VStack(alignment: .leading, spacing: 6) {
                if let snapshot = service.snapshot, let window = snapshot.primary ?? snapshot.secondary {
                    let stale = snapshot.isStale(at: timeline.date)
                    HStack(alignment: .center, spacing: 18) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(window.remainingPercent)%").font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit()
                            Text(stale ? "last reported" : "remaining").font(.system(size: 11)).foregroundStyle(.white.opacity(0.42))
                        }
                        Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(window.label).font(.system(size: 12, weight: .medium))
                            Text(resetLabel(window, now: timeline.date)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ProgressView(value: Double(window.remainingPercent), total: 100).tint(stale ? .gray : tint)
                    if snapshot.primary != nil, let weekly = snapshot.secondary {
                        Text("\(weekly.label) · \(weekly.remainingPercent)% left · \(resetLabel(weekly, now: timeline.date))")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    }
                    Text(stale ? "This reading is out of date. Refresh to check your quota." : "Subscription quota · updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9)).foregroundStyle(stale ? .orange : .white.opacity(0.35))
                    if let error = service.lastError { Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2) }
                } else {
                    EmptyFeature(symbol: "sparkle", title: service.status, detail: service.lastError ?? "Reading your subscription quota securely from Codex.", action: service.fetching ? nil : "Try again") { service.refresh() }
                }
            }
            .frame(width: 468)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                    .disabled(service.fetching).help("Refresh usage")
            }
        }
    }
    private func resetLabel(_ window: QuotaWindow, now: Date) -> String {
        guard let date = window.resetDate else { return "Reset time unavailable" }
        guard date > now else { return "Refreshing after reset" }
        let minutes = Int(ceil(date.timeIntervalSince(now) / 60))
        if minutes >= 1440 { return "Resets in \(minutes / 1440)d \(minutes / 60 % 24)h" }
        return "Resets in \(minutes / 60)h \(minutes % 60)m"
    }
}

struct BubbleView: View {
    @State private var hovered = false
    @ObservedObject var state: AppState
    var activity: ActivityID?
    var overflow: [ActivityID] = []
    var open: (ActivityID) -> Void
    var body: some View {
        Group {
            if let activity {
                Button { open(activity) } label: { content(activity).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Circle()) }
                    .help(activity == .codex ? "Codex quota remaining" : activity == .music ? "Music playback" : state.timer.countdown.name)
                    .accessibilityLabel("Open \(activity.title)")
            } else {
                Menu { ForEach(overflow) { item in Button(item.title) { open(item) } } } label: {
                    Image(systemName: "ellipsis").frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Circle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: false)
                    .accessibilityLabel("More activities, \(overflow.count) available")
            }
        }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).buttonStyle(SoftButton())
            .background {
                Circle().fill(.black)
                Circle().fill(LinearGradient(colors: [.white.opacity(hovered ? 0.12 : 0.045), .clear], startPoint: .top, endPoint: .bottom)).padding(1)
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(hovered ? 0.2 : 0.1), .white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.6)
            }.clipShape(Circle()).preferredColorScheme(.dark)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
    @ViewBuilder private func content(_ activity: ActivityID) -> some View {
        if activity == .codex {
            CircularQuota(service: state.codex, tint: state.tint)
        } else if activity == .music {
            AudioPlaybackBars(visualizer: state.visualizer, playing: state.music.track?.playing == true,
                              color: state.music.artworkAccent)
                .frame(width: 22, height: 17).allowsHitTesting(false).accessibilityHidden(true)
        } else {
            ZStack {
                ActivityRing(progress: state.timer.remaining / max(1, state.timer.countdown.duration), tint: .orange)
                if state.timer.countdown.completed { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
                else if state.timer.countdown.isPaused { Image(systemName: "timer").font(.system(size: 11)) }
                else { Text(timerLabel).font(.system(size: 9, weight: .medium)).monospacedDigit() }
            }.help("\(state.timer.countdown.name) · \(clockString(state.timer.remaining))")
        }
    }
    private var timerLabel: String {
        let seconds = Int(ceil(state.timer.remaining))
        return seconds >= 3600 ? "\(seconds / 3600)h" : seconds >= 60 ? "\(seconds / 60)m" : "\(seconds)s"
    }
}

private struct ActivityRing: View {
    var progress: Double
    var tint: Color
    var body: some View {
        Circle().trim(from: 0, to: min(1, max(0, progress)))
            .stroke(LinearGradient(colors: [tint, tint.opacity(0.45)], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 1.35, lineCap: .round))
            .rotationEffect(.degrees(-90)).padding(2.5)
            .accessibilityHidden(true)
    }
}

private struct CircularQuota: View {
    @ObservedObject var service: CodexService
    var tint: Color
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ZStack {
                if let snapshot = service.snapshot, let window = snapshot.primary ?? snapshot.secondary, !snapshot.isStale(at: timeline.date) {
                    ActivityRing(progress: Double(window.remainingPercent) / 100, tint: tint)
                    QuotaBubbleLabel(percent: window.remainingPercent)

                } else { Image(systemName: "sparkle").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)) }
            }
        }
    }
}

/// A single text run lets SwiftUI fit all four characters together at 100%.
struct QuotaBubbleLabel: View {
    let percent: Int
    var body: some View {
        Text("\(percent)%")
            .font(.system(size: 8, weight: .semibold))
            .monospacedDigit().tracking(-0.25)
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 4)
            .accessibilityLabel("\(percent) percent quota remaining")
    }
}
