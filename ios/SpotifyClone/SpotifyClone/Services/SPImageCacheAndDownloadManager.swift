import Foundation
import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - 1. Image Cache & Async View
public actor SPImageCache {
    public static let shared = SPImageCache()
    private let memory = NSCache<NSURL, AnyObject>()
    private let diskDir: URL

    private init() {
        memory.countLimit = 250
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskDir = caches.appendingPathComponent("SPImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    #if canImport(UIKit)
    public func image(for url: URL) async -> UIImage? {
        if let cached = memory.object(forKey: url as NSURL) as? UIImage {
            return cached
        }
        let keyName = String(url.absoluteString.hashValue)
        let fileURL = diskDir.appendingPathComponent(keyName)
        if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
            memory.setObject(img, forKey: url as NSURL)
            return img
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                memory.setObject(img, forKey: url as NSURL)
                try? data.write(to: fileURL)
                return img
            }
        } catch {}
        return nil
    }
    #endif
}

public struct SPCachedAsyncImage<Placeholder: View>: View {
    public let url: URL?
    @ViewBuilder public let placeholder: () -> Placeholder

    #if canImport(UIKit)
    @State private var loadedImage: UIImage?
    #endif

    public init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            #if canImport(UIKit)
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
            #else
            placeholder()
            #endif
        }
        .task(id: url) {
            guard let url = url else { return }
            #if canImport(UIKit)
            if let img = await SPImageCache.shared.image(for: url) {
                self.loadedImage = img
            }
            #endif
        }
    }
}

// MARK: - 2. Offline Audio Download Manager (Full Track .m4a / .mp3)
@MainActor
public final class SPOfflineDownloadManager: ObservableObject {
    public static let shared = SPOfflineDownloadManager()

    @Published public private(set) var downloads: [SPOfflineDownload] = []
    @Published public private(set) var activeDownloads: Set<String> = []

    private let downloadsDir: URL
    private let metadataURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.downloadsDir = docs.appendingPathComponent("SPOfflineDownloads", isDirectory: true)
        self.metadataURL = docs.appendingPathComponent("sp_offline_downloads.json")
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        loadMetadata()
    }

    public nonisolated static func localFileURL(for trackId: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        for ext in ["m4a", "mp3", "mp4"] {
            let u = docs.appendingPathComponent("SPOfflineDownloads/\(trackId).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) {
                return u
            }
        }
        return nil
    }

    public func isDownloaded(_ trackId: String) -> Bool {
        downloads.contains { $0.id == trackId }
    }

    public func downloadTrack(_ track: SPTrack) async -> Bool {
        guard !activeDownloads.contains(track.id) else { return false }
        activeDownloads.insert(track.id)
        defer { activeDownloads.remove(track.id) }

        guard let stream = await SPMusicEngine.shared.resolveAudioStream(for: track) else {
            return false
        }

        if stream.format == "m3u8" || stream.url.absoluteString.contains(".m3u8") {
            let fileName = "\(track.id).m4a"
            let dest = downloadsDir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)
            let asset = AVURLAsset(url: stream.url)
            if let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
                exporter.outputURL = dest
                exporter.outputFileType = .m4a
                await exporter.export()
                if exporter.status == .completed {
                    let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                    let entry = SPOfflineDownload(track: track, localFileName: fileName, fileSizeBytes: size, downloadedAt: Date())
                    downloads.removeAll { $0.id == track.id }
                    downloads.insert(entry, at: 0)
                    saveMetadata()
                    return true
                }
            }
            return false
        }

        let ext = stream.format == "mp3" ? "mp3" : "m4a"
        let fileName = "\(track.id).\(ext)"
        let dest = downloadsDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: dest)

        var req = URLRequest(url: stream.url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        do {
            let (tmp, resp) = try await URLSession.shared.download(for: req)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                try FileManager.default.moveItem(at: tmp, to: dest)
                let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                let entry = SPOfflineDownload(track: track, localFileName: fileName, fileSizeBytes: size, downloadedAt: Date())
                downloads.removeAll { $0.id == track.id }
                downloads.insert(entry, at: 0)
                saveMetadata()
                return true
            }
        } catch {}
        return false
    }

    public func removeDownload(trackId: String) {
        if let existing = downloads.first(where: { $0.id == trackId }) {
            let u = downloadsDir.appendingPathComponent(existing.localFileName)
            try? FileManager.default.removeItem(at: u)
        }
        downloads.removeAll { $0.id == trackId }
        saveMetadata()
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([SPOfflineDownload].self, from: data) else {
            return
        }
        self.downloads = decoded.filter { FileManager.default.fileExists(atPath: downloadsDir.appendingPathComponent($0.localFileName).path) }
    }

    private func saveMetadata() {
        if let data = try? JSONEncoder().encode(downloads) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }
}
