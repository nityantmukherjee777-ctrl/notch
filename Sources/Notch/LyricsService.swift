import Foundation
import Combine
import NotchCore

@MainActor final class LyricsService: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plain = ""
    @Published private(set) var status = "Choose a track to see lyrics"
    @Published private(set) var loading = false
    private var task: Task<Void, Never>?
    private var identity: String?
    private var cache: [String: Response] = [:]
    private struct Response: Decodable {
        var instrumental: Bool?
        var syncedLyrics: String?
        var plainLyrics: String?
    }
    func clear() { task?.cancel(); identity = nil; lines = []; plain = ""; loading = false }
    func load(_ track: Track?, retry: Bool = false) {
        guard let track else { clear(); status = "Nothing playing"; return }
        guard identity != track.identity || retry else { return }
        clear(); identity = track.identity
        if let cached = cache[track.identity], !retry { apply(cached); return }
        guard !track.artist.isEmpty else { status = "Lyrics aren’t available for this media"; return }
        loading = true; status = "Finding lyrics…"
        task = Task { [weak self] in
            var url = URLComponents(string: "https://lrclib.net/api/get")!
            url.queryItems = [URLQueryItem(name: "track_name", value: track.title), URLQueryItem(name: "artist_name", value: track.artist)]
            if !track.album.isEmpty { url.queryItems?.append(URLQueryItem(name: "album_name", value: track.album)) }
            if track.duration.isFinite, track.duration > 0 {
                let duration = Int(min(31_536_000, track.duration).rounded())
                url.queryItems?.append(URLQueryItem(name: "duration", value: String(duration)))
            }
            var request = URLRequest(url: url.url!); request.timeoutInterval = 12
            request.setValue("NotchHarbor/1.1 (personal macOS player)", forHTTPHeaderField: "User-Agent")
            do {
                let data = try await BoundedDownload.fetch(request, limit: 1_000_000, hosts: ["lrclib.net"])
                guard !Task.isCancelled, let self, self.identity == track.identity else { return }
                self.loading = false
                let result = try JSONDecoder().decode(Response.self, from: data)
                if self.cache.count >= 30 { self.cache.removeAll() }
                self.cache[track.identity] = result; self.apply(result)
            } catch {
                guard !Task.isCancelled, let self, self.identity == track.identity else { return }
                self.loading = false
                if case BoundedDownload.Failure.responseRejected(404) = error { self.status = "No lyrics found for this track" }
                else { self.status = "Couldn’t load lyrics. Check your connection." }
            }
        }
    }
    private func apply(_ response: Response) {
        loading = false
        lines = LyricsParser.parse(response.syncedLyrics ?? "")
        plain = response.plainLyrics ?? ""
        status = response.instrumental == true ? "Instrumental" : !lines.isEmpty ? "Synced lyrics · LRCLIB" : !plain.isEmpty ? "Lyrics · LRCLIB" : "No lyrics found for this track"
    }
}
