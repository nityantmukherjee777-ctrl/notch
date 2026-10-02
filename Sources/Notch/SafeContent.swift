import AppKit
import ImageIO

/// Ephemeral, bounded downloads. Limits apply while receiving bytes, not after
/// URLSession has already buffered the entire response. Redirects are validated.
final class BoundedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Failure: Error { case invalidURL, responseRejected(Int), tooLarge }
    private let limit: Int
    private let hosts: Set<String>
    private let configuration: URLSessionConfiguration?
    private let lock = NSLock()
    private var data = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var finished = false

    static func allows(_ url: URL, hosts: Set<String>) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443) && hosts.contains(url.host?.lowercased() ?? "")
    }

    static func fetch(_ request: URLRequest, limit: Int, hosts: Set<String>, configuration: URLSessionConfiguration? = nil) async throws -> Data {
        guard let url = request.url, allows(url, hosts: hosts) else { throw Failure.invalidURL }
        let download = BoundedDownload(limit: limit, hosts: hosts, configuration: configuration)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { download.begin(request, continuation: $0) }
        } onCancel: { download.finish(.failure(CancellationError())) }
    }

    private init(limit: Int, hosts: Set<String>, configuration: URLSessionConfiguration?) {
        self.limit = limit; self.hosts = hosts; self.configuration = configuration
    }
    private func begin(_ request: URLRequest, continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 20
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session; task = session.dataTask(with: request)
        let task = task
        lock.unlock()
        task?.resume()
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation, session = session
        self.continuation = nil; self.session = nil; task = nil; data = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = request.url.map { Self.allows($0, hosts: hosts) } ?? false
        completionHandler(allowed ? request : nil)
        if !allowed { finish(.failure(Failure.invalidURL)) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            completionHandler(.cancel); finish(.failure(Failure.responseRejected((response as? HTTPURLResponse)?.statusCode ?? 0))); return
        }
        guard response.expectedContentLength <= limit else {
            completionHandler(.cancel); finish(.failure(Failure.tooLarge)); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard chunk.count <= limit - data.count else {
            lock.unlock(); finish(.failure(Failure.tooLarge)); return
        }
        data.append(chunk)
        lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let result = data; lock.unlock()
        finish(error.map { .failure($0) } ?? .success(result))
    }
}

enum SafeArtwork {
    static let hosts: Set<String> = ["i.scdn.co", "mosaic.scdn.co", "image-cdn-ak.spotifycdn.com", "image-cdn-fa.spotifycdn.com"]
    static func image(_ data: Data) -> NSImage? {
        guard data.count <= 8_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 16_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}
