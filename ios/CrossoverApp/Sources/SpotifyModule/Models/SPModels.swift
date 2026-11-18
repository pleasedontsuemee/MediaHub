import Foundation

public struct SPTrack: Identifiable, Codable, Hashable {
    public let id: String
    public let title: String
    public let artistName: String
    public let artistId: String?
    public let albumTitle: String
    public let albumId: String?
    public let coverURLString: String?
    public let durationSeconds: Int
    public let previewURLString: String?
    public let directAudioURLString: String?
    public let isExplicit: Bool

    public var coverURL: URL? {
        guard let s = coverURLString, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    public var previewURL: URL? {
        guard let s = previewURLString, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    public var directAudioURL: URL? {
        guard let s = directAudioURLString, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    public var formattedDuration: String {
        let m = max(0, durationSeconds) / 60
        let s = max(0, durationSeconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    public init(
        id: String,
        title: String,
        artistName: String,
        artistId: String? = nil,
        albumTitle: String = "",
        albumId: String? = nil,
        coverURLString: String? = nil,
        durationSeconds: Int = 180,
        previewURLString: String? = nil,
        directAudioURLString: String? = nil,
        isExplicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.artistId = artistId
        self.albumTitle = albumTitle
        self.albumId = albumId
        self.coverURLString = coverURLString
        self.durationSeconds = durationSeconds
        self.previewURLString = previewURLString
        self.directAudioURLString = directAudioURLString
        self.isExplicit = isExplicit
    }
}

public struct SPCollection: Identifiable, Codable, Hashable {
    public enum Kind: String, Codable, Hashable {
        case playlist
        case album
        case artist
        case podcast
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let coverURLString: String?
    public var tracks: [SPTrack]
    public var isUserCreated: Bool

    public var coverURL: URL? {
        guard let s = coverURLString, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    public init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String = "",
        coverURLString: String? = nil,
        tracks: [SPTrack] = [],
        isUserCreated: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.coverURLString = coverURLString
        self.tracks = tracks
        self.isUserCreated = isUserCreated
    }
}

public struct SPAudioStream: Hashable {
    public let url: URL
    public let format: String // "m4a" or "mp3"
    public let sourceName: String
    public let isFullLength: Bool

    public init(url: URL, format: String, sourceName: String, isFullLength: Bool) {
        self.url = url
        self.format = format
        self.sourceName = sourceName
        self.isFullLength = isFullLength
    }
}

public struct SPOfflineDownload: Identifiable, Codable, Hashable {
    public var id: String { track.id }
    public let track: SPTrack
    public let localFileName: String
    public let fileSizeBytes: Int64
    public let downloadedAt: Date

    public var formattedSize: String {
        let mb = Double(fileSizeBytes) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", mb)
    }
}
