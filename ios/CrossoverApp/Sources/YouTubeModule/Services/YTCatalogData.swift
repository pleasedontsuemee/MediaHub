import Foundation

/// Curated YouTube catalog matching all 73 reference screenshots (AURORA, Still Watching Netflix,
/// The Current, Lofi Girl, NBC News, Massive Attack, Wednesday Addams, FIFA World Cup 2022, etc.)
/// with real YouTube video IDs so the embedded `YTInnerTubeEngine` resolves live streams directly.
public enum YTCatalogData {

    // MARK: - 1. Home Filter Chips
    public static let homeFilterChips: [String] = [
        "All",
        "New to you",
        "Mixes",
        "Gaming",
        "Music",
        "Live",
        "AURORA",
        "Jenna Ortega",
        "Wednesday Addams",
        "The Hot 100"
    ]

    public static let subscriptionsFilterChips: [String] = [
        "All",
        "Today",
        "Continue watching",
        "Unwatched",
        "Live",
        "Posts"
    ]

    // MARK: - 2. Shorts Shelf & Vertical Shorts Feed
    public static let homeShortsShelf: [YTVideo] = [
        YTVideo(
            id: "d_HlPboLRL8",
            title: "Cold Leaves FALLING SPEECHLESS ‼️...",
            channelId: "UC_vocals",
            channelTitle: "@vocalgold",
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/d_HlPboLRL8/hqdefault.jpg"),
            durationText: "0:45",
            durationSeconds: 45,
            viewCountText: "8.4M views",
            publishedTimeText: "3 days ago",
            likeCountText: "610K",
            commentCountText: "4.2K",
            isShort: true
        ),
        YTVideo(
            id: "MsXdUtlDVhk",
            title: "When The Whole Gym Watches You Lift...👀",
            channelId: "UC_gym",
            channelTitle: "@heavylifts",
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/MsXdUtlDVhk/hqdefault.jpg"),
            durationText: "0:38",
            durationSeconds: 38,
            viewCountText: "32M views",
            publishedTimeText: "1 week ago",
            likeCountText: "1.8M",
            commentCountText: "12K",
            isShort: true
        ),
        YTVideo(
            id: "NakTu_VZxJ0",
            title: "WEDNESDAY Doesn't Blink?!?! 🤯 #shorts",
            channelId: "UC_stillwatchingnetflix",
            channelTitle: "@stillwatchingnetflix",
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hqdefault.jpg"),
            durationText: "0:52",
            durationSeconds: 52,
            viewCountText: "15M views",
            publishedTimeText: "5 days ago",
            likeCountText: "920K",
            commentCountText: "5.1K",
            isShort: true
        ),
        YTVideo(
            id: "K17df81RL9Y",
            title: "Don't leave your phone with Aurora..",
            channelId: "UC_aurora",
            channelTitle: "@AuroraMusic",
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/K17df81RL9Y/hqdefault.jpg"),
            durationText: "0:34",
            durationSeconds: 34,
            viewCountText: "2.5M views",
            publishedTimeText: "2 weeks ago",
            likeCountText: "240K",
            commentCountText: "1.9K",
            isShort: true
        ),
        YTVideo(
            id: "P_XguuxLo10",
            title: "Jamie Campbell Bower doing Vecna's voice on the Tonight Show with Jimmy Fallon!",
            channelId: "UC_topfangirl14",
            channelTitle: "@topfangirl14",
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/P_XguuxLo10/hqdefault.jpg"),
            durationText: "0:59",
            durationSeconds: 59,
            viewCountText: "6.8M views",
            publishedTimeText: "4 days ago",
            likeCountText: "395K",
            commentCountText: "1.2K",
            isShort: true
        )
    ]

    // MARK: - 3. Primary Videos Matching Screenshots
    public static let videoAuroraExistForLove = YTVideo(
        id: "du34gPopP8Y",
        title: "AURORA - Exist For Love",
        channelId: "UC_aurora",
        channelTitle: "AURORA",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/du34gPopP8Y/hqdefault.jpg"),
        channelSubscribers: "4.71M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/du34gPopP8Y/hqdefault.jpg"),
        durationText: "4:20",
        durationSeconds: 260,
        viewCountText: "16M views",
        publishedTimeText: "2 years ago",
        descriptionText: "Listen to 'Exist For Love' out now from AURORA's album 'The Gods We Can Touch'. Directed by AURORA.",
        hashtags: ["#AURORA", "#ExistForLove", "#TheGodsWeCanTouch"],
        likeCountText: "412K",
        commentCountText: "18K"
    )

    public static let videoAuroraCureForMe = YTVideo(
        id: "K17df81RL9Y",
        title: "AURORA - Cure For Me (Lyric Video)",
        channelId: "UC_aurora",
        channelTitle: "AURORA",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/du34gPopP8Y/hqdefault.jpg"),
        channelSubscribers: "4.71M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/K17df81RL9Y/hq720.jpg"),
        durationText: "3:20",
        durationSeconds: 200,
        viewCountText: "1M views",
        publishedTimeText: "1 year ago",
        descriptionText: "Official Lyric Video for 'Cure For Me' by AURORA. \"But I don't need a cure for me...\"",
        hashtags: ["#AURORA", "#CureForMe", "#Lyrics"],
        likeCountText: "35K",
        commentCountText: "1K",
        watchProgress: 0.35
    )

    public static let videoAuroraRunawayLyrics = YTVideo(
        id: "d_HlPboLRL8",
        title: "AURORA - Runaway (Lyrics)",
        channelId: "UC_monstafluff",
        channelTitle: "Monstafluff Music",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/d_HlPboLRL8/hqdefault.jpg"),
        channelSubscribers: "1.82M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/d_HlPboLRL8/hq720.jpg"),
        durationText: "4:06",
        durationSeconds: 246,
        viewCountText: "92K views",
        publishedTimeText: "2 weeks ago",
        descriptionText: "AURORA - Runaway (Lyrics)\nFollow AURORA on YouTube and Spotify.",
        hashtags: ["#AURORA", "#Runaway", "#PopMusic"],
        likeCountText: "12K",
        commentCountText: "420"
    )

    public static let videoAuroraLiveTheCurrent = YTVideo(
        id: "P_XguuxLo10",
        title: "Aurora - Full performance (Live at The Current)",
        channelId: "UC_thecurrent",
        channelTitle: "The Current",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/P_XguuxLo10/hqdefault.jpg"),
        channelSubscribers: "387K subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/P_XguuxLo10/hq720.jpg"),
        durationText: "12:08",
        durationSeconds: 728,
        viewCountText: "3.2M views",
        publishedTimeText: "2 years ago",
        descriptionText: "Norwegian pop singer-songwriter Aurora performs 'Animal', 'Churchyard' and 'Forgotten Love' live in The Current studio.\n\n0:00 Animal\n3:38 Churchyard\n8:12 Forgotten Love",
        hashtags: ["#Folktronica", "#Synthpop", "#electropop"],
        likeCountText: "79K",
        commentCountText: "1.6K",
        watchProgress: 0.15
    )

    public static let videoJennaOrtegaCosplayer = YTVideo(
        id: "NakTu_VZxJ0",
        title: "Jenna Ortega Surprises a Wednesday Cosplayer | Netflix",
        channelId: "UC_stillwatchingnetflix",
        channelTitle: "Still Watching Netflix",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hqdefault.jpg"),
        channelSubscribers: "4.31M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hq720.jpg"),
        durationText: "2:17",
        durationSeconds: 137,
        viewCountText: "3.1M views",
        publishedTimeText: "4d ago",
        descriptionText: "Noor Dabash is a makeup artist and TikTok creator from Canada who gets the surprise of a lifetime from Wednesday Addams herself, Jenna Ortega!",
        hashtags: ["#Wednesday", "#JennaOrtega", "#Netflix"],
        likeCountText: "52K",
        commentCountText: "1.1K",
        watchProgress: 0.42
    )

    public static let videoWednesdayDanceScene = YTVideo(
        id: "MsXdUtlDVhk",
        title: "Wednesday Addams | Dance Scene | Netflix",
        channelId: "UC_netflix",
        channelTitle: "Netflix",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/MsXdUtlDVhk/hqdefault.jpg"),
        channelSubscribers: "25.4M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/MsXdUtlDVhk/hq720.jpg"),
        durationText: "1:23",
        durationSeconds: 83,
        viewCountText: "9.4M views",
        publishedTimeText: "11 days ago",
        descriptionText: "Watch Wednesday Addams (Jenna Ortega) perform her iconic dance scene to The Cramps' 'Goo Goo Muck' at the Rave'N Dance.",
        hashtags: ["#Wednesday", "#Netflix", "#OfficialClip"],
        likeCountText: "340K",
        commentCountText: "8.2K"
    )

    public static let videoAdamSandlerHustle = YTVideo(
        id: "nM4okRvCg2g",
        title: "How Adam Sandler Became Stanley Sugerman | Hustle | Netflix",
        channelId: "UC_stillwatchingnetflix",
        channelTitle: "Still Watching Netflix",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hqdefault.jpg"),
        channelSubscribers: "4.31M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/nM4okRvCg2g/hq720.jpg"),
        durationText: "2:41",
        durationSeconds: 161,
        viewCountText: "6K views",
        publishedTimeText: "21 hours ago",
        descriptionText: "Behind the scenes of Hustle with Adam Sandler and Juancho Hernangómez.",
        hashtags: ["#Hustle", "#AdamSandler", "#Netflix"],
        likeCountText: "890",
        commentCountText: "64"
    )

    public static let videoOndaraTheCurrent = YTVideo(
        id: "kXYiU_JCYtU",
        title: "Ondara – A Seminar in Tokyo (Microshow performance for The Current)",
        channelId: "UC_thecurrent",
        channelTitle: "The Current",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/P_XguuxLo10/hqdefault.jpg"),
        channelSubscribers: "387K subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/kXYiU_JCYtU/hq720.jpg"),
        durationText: "4:57",
        durationSeconds: 297,
        viewCountText: "166 views",
        publishedTimeText: "9 hours ago",
        descriptionText: "Ondara performs live in Minneapolis for The Current's Microshow series.",
        hashtags: ["#MICROSHOW", "#TheCurrent", "#Ondara"],
        likeCountText: "42",
        commentCountText: "7"
    )

    public static let videoMassiveAttackTeardrop = YTVideo(
        id: "u7K72X4eo_s",
        title: "Massive Attack - Teardrop (Official Video)",
        channelId: "UC_massiveattack",
        channelTitle: "massiveattack",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/u7K72X4eo_s/hqdefault.jpg"),
        channelSubscribers: "1.12M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/u7K72X4eo_s/hq720.jpg"),
        durationText: "4:55",
        durationSeconds: 295,
        viewCountText: "88M views",
        publishedTimeText: "13 years ago",
        descriptionText: "Official music video for Massive Attack - Teardrop from the album Mezzanine (1998).",
        hashtags: ["#MassiveAttack", "#Teardrop", "#Mezzanine"],
        likeCountText: "780K",
        commentCountText: "34K"
    )

    public static let videoLofiHipHopLive = YTVideo(
        id: "jfKfPfyJRdk",
        title: "lofi hip hop radio - beats to relax/study to",
        channelId: "UC_lofigirl",
        channelTitle: "Lofi Girl",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/jfKfPfyJRdk/hqdefault.jpg"),
        channelSubscribers: "14.3M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/jfKfPfyJRdk/hq720.jpg"),
        durationText: "LIVE",
        durationSeconds: 0,
        viewCountText: "44K watching",
        publishedTimeText: "Streaming live",
        descriptionText: "Thank you for listening, I hope you will have a good time here. Study & relax with Lofi Girl.",
        hashtags: ["#lofi", "#chillbeats", "#study"],
        likeCountText: "1.9M",
        commentCountText: "44K",
        isLive: true
    )

    public static let videoAddamsMakeupMGM = YTVideo(
        id: "bO3w2wU5tK0",
        title: "THE ADDAMS FAMILY | Wednesday's Makeup Tutorial | MGM",
        channelId: "UC_mgm",
        channelTitle: "MGM",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/MsXdUtlDVhk/hqdefault.jpg"),
        channelSubscribers: "4.8M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/MsXdUtlDVhk/hq720.jpg"),
        durationText: "0:52",
        durationSeconds: 52,
        viewCountText: "12M views",
        publishedTimeText: "3 years ago",
        descriptionText: "Wednesday Addams shares her signature smoky eye tutorial.",
        hashtags: ["#AddamsFamily", "#WednesdayAddams", "#MGM"],
        likeCountText: "210K",
        commentCountText: "3.1K"
    )

    public static let videoWednesdayEveryPower = YTVideo(
        id: "9bZkp7q19f0",
        title: "WEDNESDAY Season 1 EVERY Power Explained",
        channelId: "UC_brainpilot",
        channelTitle: "BrainPilot",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hqdefault.jpg"),
        channelSubscribers: "640K subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hq720.jpg"),
        durationText: "8:48",
        durationSeconds: 528,
        viewCountText: "216K views",
        publishedTimeText: "9 days ago",
        descriptionText: "Every psychic power, siren song, and outcast ability in Wednesday Season 1 explained!",
        hashtags: ["#Wednesday", "#Nevermore", "#Netflix"],
        likeCountText: "8.4K",
        commentCountText: "612"
    )

    public static let videoThat90sShowTeaser = YTVideo(
        id: "F3OxA9Cz17A",
        title: "That '90s Show | Official Teaser | Netflix",
        channelId: "UC_netflix",
        channelTitle: "Netflix",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/MsXdUtlDVhk/hqdefault.jpg"),
        channelSubscribers: "25.4M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/nM4okRvCg2g/hq720.jpg"),
        durationText: "1:07",
        durationSeconds: 67,
        viewCountText: "5.1M views",
        publishedTimeText: "6 days ago",
        descriptionText: "Hello, Wisconsin! Kurtwood Smith and Debra Jo Rupp return in That '90s Show.",
        hashtags: ["#That90sShow", "#Netflix", "#Teaser"],
        likeCountText: "145K",
        commentCountText: "6.8K"
    )

    public static let videoGuardiansGalaxy3 = YTVideo(
        id: "u3V5KDHRQvk",
        title: "Marvel Studios' Guardians of the Galaxy Volume 3 | Official Trailer",
        channelId: "UC_marvel",
        channelTitle: "Marvel Entertainment",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/u3V5KDHRQvk/hqdefault.jpg"),
        channelSubscribers: "19.8M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/u3V5KDHRQvk/hq720.jpg"),
        durationText: "1:57",
        durationSeconds: 117,
        viewCountText: "24M views",
        publishedTimeText: "5 days ago",
        descriptionText: "It's time to face the music. Watch the brand-new trailer for Marvel Studios' Guardians of the Galaxy Volume 3.",
        hashtags: ["#GotGVol3", "#MarvelStudios"],
        likeCountText: "1.1M",
        commentCountText: "58K"
    )

    public static let videoMakingOfWednesday = YTVideo(
        id: "JGwWNGJdvx8",
        title: "Making Of WEDNESDAY (2022) - Best Of Behind The Scenes & On Set Blo...",
        channelId: "UC_streamwars",
        channelTitle: "STREAM WARS",
        channelAvatarURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hqdefault.jpg"),
        channelSubscribers: "1.45M subscribers",
        isChannelVerified: true,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hq720.jpg"),
        durationText: "10:46",
        durationSeconds: 646,
        viewCountText: "3.7M views",
        publishedTimeText: "5 days ago",
        descriptionText: "Behind the scenes with Jenna Ortega, Emma Myers, and Tim Burton on the set of Wednesday.",
        hashtags: ["#Wednesday", "#BehindTheScenes"],
        likeCountText: "95K",
        commentCountText: "2.3K",
        watchProgress: 0.92
    )

    public static let videoDemoUserTestShort = YTVideo(
        id: "90s_local_test",
        title: "A test short for page flows :)",
        channelId: "UC_demouser",
        channelTitle: "Demo User",
        channelSubscribers: "No subscribers",
        isChannelVerified: false,
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/du34gPopP8Y/hq720.jpg"),
        durationText: "0:15",
        durationSeconds: 15,
        viewCountText: "0 views",
        publishedTimeText: "Dec 8, 2022 at 12:00:00 AM",
        descriptionText: "Personal test short uploaded from iPhone 16 Pro Max.",
        likeCountText: "0",
        commentCountText: "0",
        isShort: true,
        watchProgress: 1.0
    )

    // MARK: - 4. Home Feed Videos
    public static var homeFeedVideos: [YTVideo] {
        [
            videoAuroraExistForLove,
            videoAuroraRunawayLyrics,
            videoAuroraLiveTheCurrent,
            videoJennaOrtegaCosplayer,
            videoWednesdayDanceScene,
            videoAddamsMakeupMGM,
            videoWednesdayEveryPower,
            videoMakingOfWednesday,
            videoMassiveAttackTeardrop,
            videoLofiHipHopLive
        ]
    }

    // MARK: - 5. Subscribed Channels (Matches `Subscriptions` & `All subscriptions`)
    public static var defaultChannels: [YTChannel] {
        [
            YTChannel(
                id: "UC_stillwatchingnetflix",
                title: "Still Watching Netflix",
                handle: "@stillwatchingnetflix",
                avatarURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hqdefault.jpg"),
                bannerURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hq720.jpg"),
                subscribersText: "4.31M subscribers",
                videosCountText: "4.1K videos",
                descriptionText: "Still Watching Netflix is the channel that takes you deeper into the films and shows you love. Whether you're in the mood for reactions, behind-the-scenes, or cast interviews.",
                hasUnwatchedVideos: false,
                isSubscribed: true,
                notificationPreference: .personalized,
                videos: [videoJennaOrtegaCosplayer, videoAdamSandlerHustle, videoWednesdayDanceScene],
                shorts: [homeShortsShelf[2]]
            ),
            YTChannel(
                id: "UC_aurora",
                title: "AURORA",
                handle: "@AuroraMusic",
                avatarURL: URL(string: "https://i.ytimg.com/vi/du34gPopP8Y/hqdefault.jpg"),
                bannerURL: URL(string: "https://i.ytimg.com/vi/du34gPopP8Y/hq720.jpg"),
                subscribersText: "4.71M subscribers",
                videosCountText: "74 videos",
                descriptionText: "The Gods We Can Touch — Out Now everywhere.",
                hasUnwatchedVideos: false,
                isSubscribed: true,
                notificationPreference: .personalized,
                videos: [videoAuroraCureForMe, videoAuroraExistForLove, videoAuroraRunawayLyrics, videoAuroraLiveTheCurrent],
                shorts: [homeShortsShelf[3]]
            ),
            YTChannel(
                id: "UC_streamwars",
                title: "STREAM WARS",
                handle: "@streamwars",
                avatarURL: URL(string: "https://i.ytimg.com/vi/MsXdUtlDVhk/hqdefault.jpg"),
                bannerURL: URL(string: "https://i.ytimg.com/vi/MsXdUtlDVhk/hq720.jpg"),
                subscribersText: "1.45M subscribers",
                videosCountText: "320 videos",
                descriptionText: "Behind the scenes, bloopers, and cast interviews from your favorite streaming series.",
                hasUnwatchedVideos: true,
                isSubscribed: true,
                notificationPreference: .all,
                videos: [videoMakingOfWednesday, videoWednesdayEveryPower]
            ),
            YTChannel(
                id: "UC_justinschmidt",
                title: "Justin Schmidt",
                handle: "@justinschmidt",
                avatarURL: URL(string: "https://i.ytimg.com/vi/kXYiU_JCYtU/hqdefault.jpg"),
                bannerURL: URL(string: "https://i.ytimg.com/vi/kXYiU_JCYtU/hq720.jpg"),
                subscribersText: "890K subscribers",
                videosCountText: "145 videos",
                descriptionText: "Outdoor adventures, insect science, and nature documentaries.",
                hasUnwatchedVideos: true,
                isSubscribed: true,
                notificationPreference: .personalized,
                videos: [videoOndaraTheCurrent]
            ),
            YTChannel(
                id: "UC_thecurrent",
                title: "The Current",
                handle: "@TheCurrent",
                avatarURL: URL(string: "https://i.ytimg.com/vi/P_XguuxLo10/hqdefault.jpg"),
                bannerURL: URL(string: "https://i.ytimg.com/vi/P_XguuxLo10/hq720.jpg"),
                subscribersText: "387K subscribers",
                videosCountText: "2.8K videos",
                descriptionText: "Minnesota Public Radio's The Current brings you the best authentic new music alongside the music that inspired it.",
                hasUnwatchedVideos: true,
                isSubscribed: true,
                notificationPreference: .all,
                videos: [videoOndaraTheCurrent, videoAuroraLiveTheCurrent]
            )
        ]
    }

    // MARK: - 6. Live Hub Streams (Matches `GeneralBrowsing #22 & #37`)
    public static var liveHubStreams: [YTVideo] {
        [
            YTVideo(
                id: "peoples_choice_live",
                title: "🔴People's Choice Awards 2022 Red Carpet LIVESTREAM",
                channelId: "UC_enews",
                channelTitle: "E! News",
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/NakTu_VZxJ0/hq720.jpg"),
                durationText: "UPCOMING",
                durationSeconds: 0,
                viewCountText: "7 waiting",
                publishedTimeText: "Scheduled for 12/7/22, 1:00 AM",
                isLive: true,
                isUpcoming: true
            ),
            videoLofiHipHopLive,
            YTVideo(
                id: "nbc_news_live",
                title: "LIVE: NBC News NOW - Dec. 6",
                channelId: "UC_nbcnews",
                channelTitle: "NBC News",
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/u3V5KDHRQvk/hq720.jpg"),
                durationText: "LIVE",
                durationSeconds: 0,
                viewCountText: "11K watching",
                publishedTimeText: "Streaming live",
                isLive: true
            ),
            YTVideo(
                id: "day_trading_live",
                title: "🔴Watch Day Trading Live - December 6, NY Session",
                channelId: "UC_tradertv",
                channelTitle: "Live Trading by TraderTV",
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/nM4okRvCg2g/hq720.jpg"),
                durationText: "LIVE",
                durationSeconds: 0,
                viewCountText: "7.3K watching",
                publishedTimeText: "Streaming live",
                isLive: true
            )
        ]
    }

    // MARK: - 7. Trending Videos & World Cup Shelf (Matches `GeneralBrowsing #12, #13, #27`)
    public static var worldCupHighlights: [YTVideo] {
        [
            YTVideo(
                id: "wc_brazil_korea",
                title: "Rampant Brazil ease past South Korea to reach quarters-finals | World Cup 2022",
                channelId: "UC_bbcsport",
                channelTitle: "BBC Sport",
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/nM4okRvCg2g/hq720.jpg"),
                durationText: "3:04",
                durationSeconds: 184,
                viewCountText: "431K views",
                publishedTimeText: "18 hours ago"
            ),
            YTVideo(
                id: "wc_croatia_japan",
                title: "Croatia edge past Japan on penalties | World Cup 2022 Highlights",
                channelId: "UC_bbcsport",
                channelTitle: "BBC Sport",
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/u3V5KDHRQvk/hq720.jpg"),
                durationText: "3:12",
                durationSeconds: 192,
                viewCountText: "408K views",
                publishedTimeText: "20 hours ago"
            )
        ]
    }

    public static func trendingVideos(for category: String) -> [YTVideo] {
        switch category.uppercased() {
        case "MUSIC":
            return [
                YTVideo(
                    id: "nba_youngboy_supporters",
                    title: "NBA YoungBoy - This Not a Song \"This For My Supporters\"",
                    channelId: "UC_nbayoungboy",
                    channelTitle: "YoungBoy Never Broke Again",
                    thumbnailURL: URL(string: "https://i.ytimg.com/vi/kXYiU_JCYtU/hq720.jpg"),
                    durationText: "8:10",
                    durationSeconds: 490,
                    viewCountText: "1.9M views",
                    publishedTimeText: "2 days ago"
                ),
                YTVideo(
                    id: "arcangel_bad_bunny",
                    title: "Arcángel, Bad Bunny - La Jumpa (Video Oficial)",
                    channelId: "UC_rimas",
                    channelTitle: "Arcángel",
                    thumbnailURL: URL(string: "https://i.ytimg.com/vi/d_HlPboLRL8/hq720.jpg"),
                    durationText: "4:16",
                    durationSeconds: 256,
                    viewCountText: "14M views",
                    publishedTimeText: "4 days ago"
                ),
                videoAuroraExistForLove,
                videoMassiveAttackTeardrop
            ]
        case "MOVIES":
            return [
                videoThat90sShowTeaser,
                videoGuardiansGalaxy3,
                videoWednesdayDanceScene,
                videoAdamSandlerHustle
            ]
        case "GAMING":
            return [
                videoWednesdayEveryPower,
                videoMakingOfWednesday,
                videoGuardiansGalaxy3
            ]
        default: // NOW
            return [
                videoThat90sShowTeaser,
                videoGuardiansGalaxy3,
                videoJennaOrtegaCosplayer,
                videoWednesdayDanceScene
            ]
        }
    }

    // MARK: - 8. Comments Matching Screenshots (`Watching #10`, `GeneralBrowsing #15`, `Subscribing #04`)
    public static func comments(for video: YTVideo) -> [YTComment] {
        if video.id == videoJennaOrtegaCosplayer.id || video.title.localizedCaseInsensitiveContains("Wednesday") {
            return [
                YTComment(
                    authorName: "DragonFly",
                    authorHandle: "@dragonfly_cosplay",
                    publishedTimeText: "3d ago",
                    text: "The way Jenna said “It’s pretty cool huh?” sounded like she was talking to an old friend not someone she just met for the first time.",
                    likeCountText: "4.8K",
                    replyCount: 42,
                    isHeartedByCreator: true
                ),
                YTComment(
                    authorName: "Noor Dabash",
                    authorHandle: "@noordabash",
                    isVerified: true,
                    publishedTimeText: "4d ago",
                    text: "Still can't believe this happened!! Jenna is the sweetest human being ever 🖤🕷️\n0:08 My reaction when the curtain dropped!",
                    likeCountText: "12K",
                    replyCount: 118,
                    isHeartedByCreator: true
                ),
                YTComment(
                    authorName: "Demo User",
                    authorHandle: "@demouser",
                    publishedTimeText: "1d ago",
                    text: "Her Wednesday cosplay makeup is spot on!",
                    likeCountText: "215",
                    replyCount: 3
                )
            ]
        } else if video.id == videoAuroraCureForMe.id {
            return [
                YTComment(
                    authorName: "BruhANTXD",
                    authorHandle: "@BruhANTXD",
                    isVerified: true,
                    publishedTimeText: "1y ago",
                    text: "She isn't sia or billie, she is aurora",
                    likeCountText: "14K",
                    replyCount: 210,
                    isHeartedByCreator: true
                ),
                YTComment(
                    authorName: "WarriorOfLight",
                    authorHandle: "@warrioroflight",
                    publishedTimeText: "10mo ago",
                    text: "0:00 That synth intro immediately puts a smile on my face every single time.",
                    likeCountText: "3.1K",
                    replyCount: 19
                )
            ]
        }

        // Default (`Watching #10` - Aurora Live at The Current)
        return [
            YTComment(
                authorName: "Tim MacKenzie",
                authorHandle: "@timmackenzie9714",
                publishedTimeText: "2y ago",
                text: "Silja's ability to read visual and vocal cues from Aurora is magical.",
                likeCountText: "2.9K",
                replyCount: 18,
                isHeartedByCreator: true
            ),
            YTComment(
                authorName: "RowRowFightThePowaaa",
                authorHandle: "@RowRowFightThePowaaa",
                publishedTimeText: "2y ago (edited)",
                text: "I always admire people that do this so today it's my turn:\n0:00 Animal\n3:38 Churchyard ... Read more",
                likeCountText: "4.4K",
                replyCount: 39,
                isHeartedByCreator: true
            ),
            YTComment(
                authorName: "Matthew S.",
                authorHandle: "@matthewsc9718",
                publishedTimeText: "2y ago",
                text: "she sounds like a calm forest that gets a gust of wind and comes alive.",
                likeCountText: "1.2K",
                replyCount: 11
            )
        ]
    }

    // MARK: - 9. Live Chat Messages (Matches `GeneralBrowsing #24` & `Watching #14`)
    public static let liveChatMessages: [YTLiveChatMessage] = [
        YTLiveChatMessage(authorName: "👑Sofi", authorAvatarColorHex: "#F57C00", message: "привет максим"),
        YTLiveChatMessage(authorName: "Aboody", authorAvatarColorHex: "#00695C", message: "اليمن وعايش في السعوديه"),
        YTLiveChatMessage(authorName: "♡Diamond Queen♡", authorAvatarColorHex: "#8E24AA", message: "Batman ooh not good, I'm sorry (◞‸◟⁰⁰)"),
        YTLiveChatMessage(authorName: "Lily", authorAvatarColorHex: "#1565C0", message: "Einstein not in a good mood to tell jokes really /:"),
        YTLiveChatMessage(authorName: "Seren", authorAvatarColorHex: "#2E7D32", message: "@Caroline hy sk is here ?"),
        YTLiveChatMessage(authorName: "Armaan", authorAvatarColorHex: "#C62828", message: "@William B lol yeah"),
        YTLiveChatMessage(authorName: "Hori", authorAvatarColorHex: "#4527A0", message: "goodnight"),
        YTLiveChatMessage(authorName: "jiggrinder", authorAvatarColorHex: "#F9A825", message: "I saw Aurora in Milwaukee and have never been the same"),
        YTLiveChatMessage(authorName: "Jay Bee Jay", authorAvatarColorHex: "#4A148C", message: "saw her in Montreal last March, same"),
        YTLiveChatMessage(authorName: "Kristin Born", authorAvatarColorHex: "#37474F", message: "@jiggrinder lol")
    ]

    // MARK: - 10. Related Videos & Fallback Search
    public static func relatedVideos(for video: YTVideo) -> [YTVideo] {
        let all = homeFeedVideos + [videoAdamSandlerHustle, videoOndaraTheCurrent, videoThat90sShowTeaser, videoGuardiansGalaxy3]
        return all.filter { $0.id != video.id }
    }

    public static func fallbackSearch(for query: String) -> [YTVideo] {
        let q = query.lowercased()
        let pool = homeFeedVideos + [videoAuroraCureForMe, videoAdamSandlerHustle, videoOndaraTheCurrent, videoThat90sShowTeaser, videoGuardiansGalaxy3]
        let matches = pool.filter {
            $0.title.lowercased().contains(q) ||
            $0.channelTitle.lowercased().contains(q) ||
            $0.hashtags.joined(separator: " ").lowercased().contains(q)
        }
        return matches.isEmpty ? pool : matches
    }

    public static func defaultCaptions(forVideoTitle title: String) -> [YTCaptionCue] {
        [
            YTCaptionCue(startTime: 0, duration: 4, text: "[Music]"),
            YTCaptionCue(startTime: 4, duration: 5, text: "Hi, my name is Noor Dabash"),
            YTCaptionCue(startTime: 9, duration: 6, text: "and I am a makeup artist slash TikTok creator from Canada."),
            YTCaptionCue(startTime: 15, duration: 6, text: "I wanted to go like half in between the original Wednesday"),
            YTCaptionCue(startTime: 21, duration: 6, text: "and Jenna Ortega's new portrayal at Nevermore Academy."),
            YTCaptionCue(startTime: 27, duration: 10, text: "[Music] ♪ Hunting for love, hunting for love ♪")
        ]
    }
}
