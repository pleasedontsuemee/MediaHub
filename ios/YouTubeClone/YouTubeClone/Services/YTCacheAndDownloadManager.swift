import Foundation
import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - 1. Persistent Image & Metadata Cache
public final class YTImageCache: @unchecked Sendable {
    public static let shared = YTImageCache()

    #if canImport(UIKit)
    private let memoryCache = NSCache<NSString, UIImage>()
    #endif
    private let diskDirectory: URL
    private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskDirectory = caches.appendingPathComponent("YTThumbnailCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)

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
        let diskURL = diskDirectory.appendingPathComponent(fileName)
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
            // Automatic fallback from /hq720.jpg to /hqdefault.jpg if 404
            if url.absoluteString.contains("hq720.jpg"),
               let fallbackURL = URL(string: url.absoluteString.replacingOccurrences(of: "hq720.jpg", with: "hqdefault.jpg")) {
                let (fData, fResp) = try await session.data(from: fallbackURL)
                if let fHttp = fResp as? HTTPURLResponse, (200..<300).contains(fHttp.statusCode),
                   let fImg = UIImage(data: fData) {
                    memoryCache.setObject(fImg, forKey: key)
                    try? fData.write(to: diskURL, options: .atomic)
                    return fImg
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    #endif
}

// MARK: - Cached Async Thumbnail / Avatar View with Shimmer
public struct YTCachedAsyncImage<Placeholder: View>: View {
    public let url: URL?
    public let contentMode: ContentMode
    public let placeholder: () -> Placeholder

    #if canImport(UIKit)
    @State private var loadedImage: UIImage?
    #endif
    @State private var isLoading = true

    public init(
        url: URL?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
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
            guard let url = url else {
                isLoading = false
                return
            }
            #if canImport(UIKit)
            if let img = await YTImageCache.shared.image(for: url) {
                self.loadedImage = img
            }
            #endif
            self.isLoading = false
        }
    }
}

// MARK: - 2. Offline Video Download Manager
@MainActor
public final class YTOfflineDownloadManager: ObservableObject {
    public static let shared = YTOfflineDownloadManager()

    @Published public private(set) var downloads: [YTOfflineDownload] = []
    @Published public private(set) var activeDownloadProgress: [String: Double] = [:]

    private let downloadsDir: URL
    private let metadataURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.downloadsDir = docs.appendingPathComponent("YTOfflineDownloads", isDirectory: true)
        self.metadataURL = docs.appendingPathComponent("yt_offline_downloads.json")
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        loadMetadata()
    }

    public nonisolated static func localFileURL(forVideoId videoId: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let mp4URL = docs.appendingPathComponent("YTOfflineDownloads/\(videoId).mp4")
        if FileManager.default.fileExists(atPath: mp4URL.path) {
            return mp4URL
        }
        let m4aURL = docs.appendingPathComponent("YTOfflineDownloads/\(videoId).m4a")
        if FileManager.default.fileExists(atPath: m4aURL.path) {
            return m4aURL
        }
        return nil
    }

    public func isDownloaded(_ videoId: String) -> Bool {
        downloads.contains { $0.id == videoId }
    }

    public func downloadVideo(_ video: YTVideo, quality: String = "360p") async -> Bool {
        if isDownloaded(video.id) {
            removeDownload(videoId: video.id)
        }
        activeDownloadProgress[video.id] = 0.05
        YTDebugLogger.shared.log(.stream, tag: "Download", "Starting download \(video.id) quality=\(quality)")

        let resolved = await YTInnerTubeEngine.shared.resolveVideoPlayback(for: video)
        let ua = "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"

        // Case 1: Audio-Only M4A Download (Music / Podcast)
        // Uses `muxedFormats.first` (`itag 18`, immune to adaptive 403 limits) and extracts a clean `.m4a` AAC track via AVAssetExportSession!
        if quality.localizedCaseInsensitiveContains("Audio") {
            let destM4A = downloadsDir.appendingPathComponent("\(video.id).m4a")
            if let muxed = resolved.muxedFormats.first {
                let tmpMP4 = FileManager.default.temporaryDirectory.appendingPathComponent("\(video.id)_audsrc.mp4")
                activeDownloadProgress[video.id] = 0.25
                if await downloadSingleFile(from: muxed.url, to: tmpMP4, userAgent: ua) {
                    activeDownloadProgress[video.id] = 0.75
                    if await extractAudioOnlyM4A(from: tmpMP4, to: destM4A) {
                        try? FileManager.default.removeItem(at: tmpMP4)
                        let size = ((try? FileManager.default.attributesOfItem(atPath: destM4A.path))?[.size] as? Int64) ?? 3_500_000
                        let item = YTOfflineDownload(
                            video: resolved.video,
                            localFileName: "\(video.id).m4a",
                            qualityLabel: "Audio M4A",
                            fileSizeBytes: size,
                            downloadedAt: Date()
                        )
                        downloads.insert(item, at: 0)
                        saveMetadata()
                        activeDownloadProgress.removeValue(forKey: video.id)
                        YTDebugLogger.shared.log(.stream, tag: "Download", "Saved Audio M4A \(video.id) (\(size) bytes)")
                        return true
                    }
                    try? FileManager.default.removeItem(at: tmpMP4)
                }
            }
            activeDownloadProgress.removeValue(forKey: video.id)
            return false
        }

        // Case 2: Video Download at Selected Resolution (`144p`..`2160p 4K`)
        let destinationMP4 = downloadsDir.appendingPathComponent("\(video.id).mp4")
        let chosenFmt = resolved.matchingVideoFormat(for: quality) ?? resolved.muxedFormats.first ?? resolved.adaptiveVideoFormats.first

        if let fmt = chosenFmt {
            if fmt.isMuxed {
                if await downloadSingleFile(from: fmt.url, to: destinationMP4, userAgent: ua) {
                    let size = ((try? FileManager.default.attributesOfItem(atPath: destinationMP4.path))?[.size] as? Int64) ?? 12_500_000
                    let item = YTOfflineDownload(
                        video: resolved.video,
                        localFileName: "\(video.id).mp4",
                        qualityLabel: fmt.displayResolutionTitle,
                        fileSizeBytes: size,
                        downloadedAt: Date()
                    )
                    downloads.insert(item, at: 0)
                    saveMetadata()
                    activeDownloadProgress.removeValue(forKey: video.id)
                    return true
                }
            } else if let audioFmt = resolved.bestAudioFormat {
                let tmpVideo = FileManager.default.temporaryDirectory.appendingPathComponent("\(video.id)_v.mp4")
                let tmpAudio = FileManager.default.temporaryDirectory.appendingPathComponent("\(video.id)_a.m4a")
                activeDownloadProgress[video.id] = 0.25

                async let vOk = downloadSingleFile(from: fmt.url, to: tmpVideo, userAgent: ua)
                async let aOk = downloadSingleFile(from: audioFmt.url, to: tmpAudio, userAgent: ua)
                let (vDone, aDone) = await (vOk, aOk)

                if vDone && aDone {
                    activeDownloadProgress[video.id] = 0.80
                    if await mergeVideoAndAudio(videoURL: tmpVideo, audioURL: tmpAudio, outputURL: destinationMP4) {
                        try? FileManager.default.removeItem(at: tmpVideo)
                        try? FileManager.default.removeItem(at: tmpAudio)
                        let size = ((try? FileManager.default.attributesOfItem(atPath: destinationMP4.path))?[.size] as? Int64) ?? 25_000_000
                        let item = YTOfflineDownload(
                            video: resolved.video,
                            localFileName: "\(video.id).mp4",
                            qualityLabel: fmt.displayResolutionTitle,
                            fileSizeBytes: size,
                            downloadedAt: Date()
                        )
                        downloads.insert(item, at: 0)
                        saveMetadata()
                        activeDownloadProgress.removeValue(forKey: video.id)
                        YTDebugLogger.shared.log(.stream, tag: "Download", "Saved \(fmt.displayResolutionTitle) MP4 \(video.id) (\(size) bytes)")
                        return true
                    }
                }
                try? FileManager.default.removeItem(at: tmpVideo)
                try? FileManager.default.removeItem(at: tmpAudio)

                // Fallback to muxed 360p if passthrough merge wasn't supported for this codec
                if let muxed = resolved.muxedFormats.first,
                   await downloadSingleFile(from: muxed.url, to: destinationMP4, userAgent: ua) {
                    let size = ((try? FileManager.default.attributesOfItem(atPath: destinationMP4.path))?[.size] as? Int64) ?? 12_500_000
                    let item = YTOfflineDownload(
                        video: resolved.video,
                        localFileName: "\(video.id).mp4",
                        qualityLabel: muxed.displayResolutionTitle,
                        fileSizeBytes: size,
                        downloadedAt: Date()
                    )
                    downloads.insert(item, at: 0)
                    saveMetadata()
                    activeDownloadProgress.removeValue(forKey: video.id)
                    return true
                }
            }
        }

        activeDownloadProgress.removeValue(forKey: video.id)
        return false
    }

    private func downloadSingleFile(from url: URL, to destination: URL, userAgent: String) async -> Bool {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (tempURL, resp) = try await URLSession.shared.download(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            return true
        } catch {
            YTDebugLogger.shared.log(.error, tag: "Download", "File download error: \(error.localizedDescription)")
            return false
        }
    }

    private func mergeVideoAndAudio(videoURL: URL, audioURL: URL, outputURL: URL) async -> Bool {
        let composition = AVMutableComposition()
        let vAsset = AVURLAsset(url: videoURL)
        let aAsset = AVURLAsset(url: audioURL)

        do {
            let vTracks = try await vAsset.loadTracks(withMediaType: .video)
            let aTracks = try await aAsset.loadTracks(withMediaType: .audio)
            guard let vTrack = vTracks.first, let aTrack = aTracks.first else { return false }

            let vDur = try await vAsset.load(.duration)
            let aDur = try await aAsset.load(.duration)
            let minDur = CMTimeMinimum(vDur, aDur)

            guard let compV = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let compA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                return false
            }

            try compV.insertTimeRange(CMTimeRange(start: .zero, duration: minDur), of: vTrack, at: .zero)
            try compA.insertTimeRange(CMTimeRange(start: .zero, duration: minDur), of: aTrack, at: .zero)

            try? FileManager.default.removeItem(at: outputURL)
            guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                return false
            }
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true
            await exporter.export()
            return exporter.status == .completed
        } catch {
            YTDebugLogger.shared.log(.error, tag: "DownloadMux", "Mux failed: \(error.localizedDescription)")
            return false
        }
    }

    private func extractAudioOnlyM4A(from sourceMP4: URL, to outputM4A: URL) async -> Bool {
        let asset = AVURLAsset(url: sourceMP4)
        let composition = AVMutableComposition()
        do {
            let aTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let aTrack = aTracks.first,
                  let compA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                return false
            }
            let dur = try await asset.load(.duration)
            try compA.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: aTrack, at: .zero)

            try? FileManager.default.removeItem(at: outputM4A)
            guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
                    ?? AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                return false
            }
            exporter.outputURL = outputM4A
            exporter.outputFileType = .m4a
            await exporter.export()
            return exporter.status == .completed
        } catch {
            YTDebugLogger.shared.log(.error, tag: "DownloadAudio", "M4A extraction failed: \(error.localizedDescription)")
            return false
        }
    }

    public func removeDownload(videoId: String) {
        let mp4URL = downloadsDir.appendingPathComponent("\(videoId).mp4")
        let m4aURL = downloadsDir.appendingPathComponent("\(videoId).m4a")
        try? FileManager.default.removeItem(at: mp4URL)
        try? FileManager.default.removeItem(at: m4aURL)
        downloads.removeAll { $0.id == videoId }
        saveMetadata()
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([YTOfflineDownload].self, from: data) else {
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
