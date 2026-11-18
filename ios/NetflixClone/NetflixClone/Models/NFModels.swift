import Foundation

// MARK: - Media Type
public enum NFMediaType: String, Codable, Hashable {
    case movie
    case tv

    public var badgeLabel: String {
        switch self {
        case .movie: return "FILM"
        case .tv: return "SERIES"
        }
    }
}

// MARK: - Movie / Series Item
public struct NFMediaItem: Identifiable, Codable, Hashable {
    public let id: Int
    public let mediaType: NFMediaType
    public let title: String
    public let originalTitle: String
    public let overview: String
    public let posterPath: String?
    public let backdropPath: String?
    public let releaseDate: String
    public let voteAverage: Double
    public let genreIds: [Int]
    public var genreNames: [String]
    public var runtimeMinutes: Int?
    public var numberOfSeasons: Int?
    public var maturityRating: String
    public var badgeText: String?
    public var top10Rank: Int?
    public var watchProgress: Double // 0.0 ... 1.0
    public var lastSeasonNumber: Int?
    public var lastEpisodeNumber: Int?

    public var posterURL: URL? {
        guard let p = posterPath, !p.isEmpty else { return nil }
        if p.hasPrefix("http") { return URL(string: p) }
        return URL(string: "https://image.tmdb.org/t/p/w500\(p)")
    }

    public var backdropURL: URL? {
        if let b = backdropPath, !b.isEmpty {
            if b.hasPrefix("http") { return URL(string: b) }
            return URL(string: "https://image.tmdb.org/t/p/w1280\(b)")
        }
        return posterURL
    }

    public var releaseYear: String {
        String(releaseDate.prefix(4))
    }

    public var metadataLine: String {
        var parts: [String] = []
        if !releaseYear.isEmpty { parts.append(releaseYear) }
        if mediaType == .tv, let seasons = numberOfSeasons, seasons > 0 {
            parts.append(seasons == 1 ? "1 Saison" : "\(seasons) Saisons")
        } else if let rt = runtimeMinutes, rt > 0 {
            let h = rt / 60
            let m = rt % 60
            parts.append(h > 0 ? "\(h)h \(m)m" : "\(m)m")
        }
        return parts.joined(separator: "  ")
    }

    public init(
        id: Int,
        mediaType: NFMediaType,
        title: String,
        originalTitle: String = "",
        overview: String = "",
        posterPath: String? = nil,
        backdropPath: String? = nil,
        releaseDate: String = "",
        voteAverage: Double = 7.5,
        genreIds: [Int] = [],
        genreNames: [String] = [],
        runtimeMinutes: Int? = nil,
        numberOfSeasons: Int? = nil,
        maturityRating: String = "16+",
        badgeText: String? = nil,
        top10Rank: Int? = nil,
        watchProgress: Double = 0.0,
        lastSeasonNumber: Int? = nil,
        lastEpisodeNumber: Int? = nil
    ) {
        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.originalTitle = originalTitle.isEmpty ? title : originalTitle
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseDate = releaseDate
        self.voteAverage = voteAverage
        self.genreIds = genreIds
        self.genreNames = genreNames
        self.runtimeMinutes = runtimeMinutes
        self.numberOfSeasons = numberOfSeasons
        self.maturityRating = maturityRating
        self.badgeText = badgeText
        self.top10Rank = top10Rank
        self.watchProgress = watchProgress
        self.lastSeasonNumber = lastSeasonNumber
        self.lastEpisodeNumber = lastEpisodeNumber
    }
}

// MARK: - Home Lolomo Row
public struct NFMediaRow: Identifiable, Hashable {
    public enum RowStyle: Hashable {
        case standard
        case top10
        case continueWatching
    }

    public let id: String
    public let title: String
    public let style: RowStyle
    public var items: [NFMediaItem]

    public init(id: String = UUID().uuidString, title: String, style: RowStyle = .standard, items: [NFMediaItem]) {
        self.id = id
        self.title = title
        self.style = style
        self.items = items
    }
}

// MARK: - TV Season & Episode
public struct NFSeason: Identifiable, Hashable, Codable {
    public var id: Int { seasonNumber }
    public let seasonNumber: Int
    public let name: String
    public let episodeCount: Int
}

public struct NFEpisode: Identifiable, Hashable, Codable {
    public let id: Int
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let name: String
    public let overview: String
    public let runtime: Int
    public let stillPath: String?

    public var stillURL: URL? {
        guard let s = stillPath, !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: "https://image.tmdb.org/t/p/w500\(s)")
    }
}

// MARK: - Movix Playable Stream Source
public struct NFStreamSource: Identifiable, Hashable, Codable {
    public var id: String { "\(provider)_\(language)_\(url.absoluteString)" }
    public let url: URL
    public let name: String
    public let provider: String
    public let format: String // "m3u8", "mp4", or "embed"
    public let quality: String
    public let language: String
    public let isEmbed: Bool
    public let referer: String?

    public init(
        url: URL,
        name: String,
        provider: String = "Movix",
        format: String = "m3u8",
        quality: String = "1080p",
        language: String = "MULTI",
        isEmbed: Bool = false,
        referer: String? = nil
    ) {
        self.url = url
        self.name = name
        self.provider = provider
        self.format = format
        self.quality = quality
        self.language = language
        self.isEmbed = isEmbed
        self.referer = referer
    }
}

// MARK: - User Profile
public struct NFProfile: Identifiable, Codable, Hashable {
    public let id: String
    public var name: String
    public var colorHex: String
    public var avatarName: String
    public var isKids: Bool

    public init(id: String = UUID().uuidString, name: String, colorHex: String, avatarName: String = "avatar_squid", isKids: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.avatarName = avatarName
        self.isKids = isKids
    }
}

// MARK: - Offline Downloaded Item
public struct NFOfflineDownload: Identifiable, Codable, Hashable {
    public var id: String { "\(media.mediaType.rawValue)_\(media.id)_s\(seasonNumber ?? 0)_e\(episodeNumber ?? 0)" }
    public let media: NFMediaItem
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeTitle: String?
    public let localFileName: String
    public let qualityLabel: String
    public let fileSizeBytes: Int64
    public let downloadedAt: Date

    public var formattedSize: String {
        let mb = Double(fileSizeBytes) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", mb)
    }
}
