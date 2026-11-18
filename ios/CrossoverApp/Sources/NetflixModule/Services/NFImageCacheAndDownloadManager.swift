import Foundation
import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - 1. Persistent Image Cache (`NFImageCache`)
public final class NFImageCache: @unchecked Sendable {
    public static let shared = NFImageCache()

    #if canImport(UIKit)
    private let memoryCache = NSCache<NSString, UIImage>()
    #endif
    private let diskDir: URL
    private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskDir = caches.appendingPathComponent("NFImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    #if canImport(UIKit)
    public func image(for url: URL) async -> UIImage? {
        let key = NSString(string: url.absoluteString)
        if let mem = memoryCache.object(forKey: key) {
            return mem
        }

        let fileName = String(url.absoluteString.hashValue) + ".jpg"
        let diskURL = diskDir.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: diskURL), let img = UIImage(data: data) {
            memoryCache.setObject(img, forKey: key)
            return img
        }

        do {
            let (data, resp) = try await session.data(from: url)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let img = UIImage(data: data) {
                memoryCache.setObject(img, forKey: key)
                try? data.write(to: diskURL, options: .atomic)
                return img
            }
        } catch {}
        return nil
    }
    #endif
}

public struct NFCachedAsyncImage<Placeholder: View>: View {
    public let url: URL?
    public let contentMode: ContentMode
    public let placeholder: () -> Placeholder

    #if canImport(UIKit)
    @State private var loadedImage: UIImage?
    #endif

    public init(url: URL?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    public var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
            #else
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().aspectRatio(contentMode: contentMode)
                } else {
                    placeholder()
                }
            }
            #endif
        }
        .task(id: url) {
            guard let url = url else { return }
            #if canImport(UIKit)
            if let img = await NFImageCache.shared.image(for: url) {
                self.loadedImage = img
            }
            #endif
        }
    }
}

// MARK: - 2. Offline Download Manager (`NFOfflineDownloadManager`)
@MainActor
public final class NFOfflineDownloadManager: ObservableObject {
    public static let shared = NFOfflineDownloadManager()

    @Published public private(set) var downloads: [NFOfflineDownload] = []
    @Published public private(set) var activeProgress: [String: Double] = [:]

    private let downloadsDir: URL
    private let metadataURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.downloadsDir = docs.appendingPathComponent("NFOfflineDownloads", isDirectory: true)
        self.metadataURL = docs.appendingPathComponent("nf_offline_downloads.json")
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        loadMetadata()
    }

    public nonisolated static func localFileURL(for idKey: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        for ext in ["mp4", "movpkg", "m4a"] {
            let u = docs.appendingPathComponent("NFOfflineDownloads/\(idKey).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) {
                return u
            }
        }
        return nil
    }

    public func key(for media: NFMediaItem, season: Int?, episode: Int?) -> String {
        "\(media.mediaType.rawValue)_\(media.id)_s\(season ?? 0)_e\(episode ?? 0)"
    }

    public func isDownloaded(media: NFMediaItem, season: Int? = nil, episode: Int? = nil) -> Bool {
        let k = key(for: media, season: season, episode: episode)
        return downloads.contains { $0.id == k }
    }

    public func downloadMedia(
        _ media: NFMediaItem,
        season: Int? = nil,
        episode: Int? = nil,
        episodeTitle: String? = nil,
        qualityLabel: String = "1080p"
    ) async -> Bool {
        let k = key(for: media, season: season, episode: episode)
        activeProgress[k] = 0.1
        NFDebugLogger.shared.log(.stream, tag: "Download", "Starting offline download for \(k)")

        let sources = await NFMovixEngine.shared.resolveMovixStreams(for: media, season: season, episode: episode)
        var resolvedSource: NFStreamSource? = sources.first(where: { !$0.isEmbed })
        if resolvedSource == nil, let firstEmbed = sources.first {
            resolvedSource = await NFMovixEngine.shared.extractDirectStream(from: firstEmbed)
        }
        guard let source = resolvedSource else {
            activeProgress.removeValue(forKey: k)
            NFDebugLogger.shared.log(.error, tag: "Download", "No direct stream sources found for \(k)")
            return false
        }

        let destMP4 = downloadsDir.appendingPathComponent("\(k).mp4")
        try? FileManager.default.removeItem(at: destMP4)

        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15"
        ]
        if let ref = source.referer {
            headers["Referer"] = ref
        }

        if source.format == "mp4" || source.url.pathExtension.lowercased() == "mp4" {
            var req = URLRequest(url: source.url)
            for (hk, hv) in headers { req.setValue(hv, forHTTPHeaderField: hk) }
            if let (tmp, resp) = try? await URLSession.shared.download(for: req),
               let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                try? FileManager.default.moveItem(at: tmp, to: destMP4)
                recordSuccess(media: media, season: season, episode: episode, episodeTitle: episodeTitle, fileName: "\(k).mp4", destURL: destMP4, qualityLabel: qualityLabel)
                activeProgress.removeValue(forKey: k)
                return true
            }
        } else {
            // Export HLS .m3u8 stream to offline .mp4 using AVAssetExportSession
            let asset = AVURLAsset(url: source.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            activeProgress[k] = 0.35
            if let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) {
                exporter.outputURL = destMP4
                exporter.outputFileType = .mp4
                exporter.shouldOptimizeForNetworkUse = true
                await exporter.export()
                if exporter.status == .completed {
                    recordSuccess(media: media, season: season, episode: episode, episodeTitle: episodeTitle, fileName: "\(k).mp4", destURL: destMP4, qualityLabel: qualityLabel)
                    activeProgress.removeValue(forKey: k)
                    NFDebugLogger.shared.log(.stream, tag: "Download", "Exported HLS -> MP4 offline for \(k)")
                    return true
                } else {
                    NFDebugLogger.shared.log(.error, tag: "Download", "HLS export failed: \(exporter.error?.localizedDescription ?? "unknown")")
                }
            }
        }

        activeProgress.removeValue(forKey: k)
        return false
    }

    private func recordSuccess(
        media: NFMediaItem,
        season: Int?,
        episode: Int?,
        episodeTitle: String?,
        fileName: String,
        destURL: URL,
        qualityLabel: String
    ) {
        let size = ((try? FileManager.default.attributesOfItem(atPath: destURL.path))?[.size] as? Int64) ?? 25_000_000
        let item = NFOfflineDownload(
            media: media,
            seasonNumber: season,
            episodeNumber: episode,
            episodeTitle: episodeTitle,
            localFileName: fileName,
            qualityLabel: qualityLabel,
            fileSizeBytes: size,
            downloadedAt: Date()
        )
        downloads.removeAll { $0.id == item.id }
        downloads.insert(item, at: 0)
        saveMetadata()
    }

    public func removeDownload(id: String) {
        for ext in ["mp4", "movpkg", "m4a"] {
            let u = downloadsDir.appendingPathComponent("\(id).\(ext)")
            try? FileManager.default.removeItem(at: u)
        }
        downloads.removeAll { $0.id == id }
        saveMetadata()
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([NFOfflineDownload].self, from: data) else {
            return
        }
        self.downloads = decoded
    }

    private func saveMetadata() {
        if let data = try? JSONEncoder().encode(downloads) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }
}
