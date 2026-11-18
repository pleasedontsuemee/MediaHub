import SwiftUI

// MARK: - 1. Active Search & Autocomplete Overlay (`GeneralBrowsing #39` & `Searching #03, #06, #07, #08`)
public struct YTSearchOverlayView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @FocusState private var isInputFocused: Bool
    @State private var swipedItem: String? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Search Input Bar
            HStack(spacing: 12) {
                Button {
                    isInputFocused = false
                    appVM.isSearchOverlayPresented = false
                } label: {
                    YTIcon("yt_outline_arrow_left_24pt", fallback: "arrow.left", size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                TextField("Search YouTube", text: $appVM.searchQuery)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(YTTheme.textPrimary)
                    .tint(YTTheme.callToActionBlue)
                    .focused($isInputFocused)
                    .submitLabel(.search)
                    .onChange(of: appVM.searchQuery) { _, newValue in
                        appVM.updateSearchSuggestions(for: newValue)
                    }
                    .onSubmit {
                        appVM.submitSearch(appVM.searchQuery)
                    }

                if !appVM.searchQuery.isEmpty {
                    Button {
                        appVM.searchQuery = ""
                        appVM.updateSearchSuggestions(for: "")
                    } label: {
                        YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                            .foregroundStyle(YTTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        appVM.showToast("Listening for voice search...")
                    } label: {
                        YTIcon("yt_outline_mic_24pt", fallback: "mic", size: 24)
                            .foregroundStyle(YTTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(YTTheme.backgroundPrimary)
            .overlay(alignment: .bottom) {
                Rectangle().fill(YTTheme.separator).frame(height: 0.5)
            }

            // Combined Autocomplete Suggestions + Search History with Swipe-to-Delete (`Searching #06, #07, #08`)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Live Autocomplete Suggestions (Magnifying glass icon on left)
                    ForEach(appVM.searchSuggestions, id: \.self) { suggestion in
                        HStack(spacing: 18) {
                            YTIcon("yt_outline_search_24pt", fallback: "magnifyingglass", size: 22)
                                .foregroundStyle(YTTheme.textPrimary)

                            Button {
                                appVM.submitSearch(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(YTTheme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button {
                                appVM.searchQuery = suggestion
                            } label: {
                                YTIcon("yt_outline_arrow_diagonal_24pt", fallback: "arrow.up.left", size: 20)
                                    .foregroundStyle(YTTheme.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(YTTheme.backgroundPrimary)
                    }

                    // Search History Rows (Clock history icon on left + Swipe-left red DELETE button)
                    ForEach(appVM.searchHistory, id: \.self) { historyItem in
                        YTSearchHistorySwipeRow(
                            item: historyItem,
                            isSwiped: swipedItem == historyItem,
                            onSetSwiped: { open in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    swipedItem = open ? historyItem : nil
                                }
                            },
                            onSelect: {
                                appVM.submitSearch(historyItem)
                            },
                            onFillQuery: {
                                appVM.searchQuery = historyItem
                            },
                            onDelete: {
                                appVM.deleteSearchHistoryItem(historyItem)
                                swipedItem = nil
                            }
                        )
                    }
                }
            }
            .background(Color.black.opacity(0.45))
        }
        .onAppear {
            appVM.updateSearchSuggestions(for: appVM.searchQuery)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }
}

// MARK: - Search History Swipe-to-Delete Row (`Searching #07` red DELETE button)
private struct YTSearchHistorySwipeRow: View {
    let item: String
    let isSwiped: Bool
    let onSetSwiped: (Bool) -> Void
    let onSelect: () -> Void
    let onFillQuery: () -> Void
    let onDelete: () -> Void

    @State private var dragX: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            // Red DELETE Action Behind Row
            Button {
                onDelete()
            } label: {
                Text("DELETE")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 86, height: 48)
                    .background(YTTheme.color(hex: "#DC1414"))
            }
            .buttonStyle(.plain)

            // Foreground Row
            HStack(spacing: 18) {
                YTIcon("ic_history", fallback: "clock.arrow.circlepath", size: 22)
                    .foregroundStyle(YTTheme.textPrimary)

                Button(action: onSelect) {
                    Text(item)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: onFillQuery) {
                    YTIcon("yt_outline_arrow_diagonal_24pt", fallback: "arrow.up.left", size: 20)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(YTTheme.backgroundPrimary)
            .offset(x: isSwiped ? -86 : min(0, dragX))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { val in
                        if val.translation.width < 0 {
                            dragX = max(-96, val.translation.width)
                        } else if isSwiped {
                            dragX = min(0, -86 + val.translation.width)
                        }
                    }
                    .onEnded { val in
                        if val.translation.width < -35 {
                            onSetSwiped(true)
                        } else {
                            onSetSwiped(false)
                        }
                        dragX = 0
                    }
            )
        }
        .clipped()
    }
}

// MARK: - 2. Search Results View (`GeneralBrowsing #02, #04, #18` & `Searching #02, #04, #09`)
public struct YTSearchResultsView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    public let query: String

    @State private var showFiltersSheet: Bool = false

    public init(query: String) {
        self.query = query
    }

    private var contextualChips: [String] {
        let q = query.lowercased()
        if q.contains("massive attack") || q.contains("teardrop") {
            return ["All", "House", "Lyrics", "Remix", "Cover"]
        } else if q.contains("pop music") {
            return ["All", "Videos", "Clean", "2020", "2021", "Songs"]
        } else {
            return ["All", "Shorts", "Recently uploaded", "Subscriptions", "Watched"]
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Search Results Bar (`←`, query text, `✕`, Cast, Filter sliders)
            HStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    YTIcon("yt_outline_arrow_left_24pt", fallback: "arrow.left", size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Button {
                    appVM.searchQuery = query
                    appVM.isSearchOverlayPresented = true
                } label: {
                    Text(query)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    appVM.searchQuery = ""
                    appVM.isSearchOverlayPresented = true
                } label: {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Button {
                    appVM.isCastAlertPresented = true
                } label: {
                    YTIcon("yt_outline_chromecast_24pt", fallback: "tv.badge.wifi", size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Button {
                    showFiltersSheet = true
                } label: {
                    YTIcon("yt_outline_menu_filter_24pt", fallback: "slider.horizontal.3", size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(YTTheme.backgroundPrimary)

            // Contextual Filter Chips (`All`, `Shorts`, `Recently uploaded`, `Subscriptions` / `House`, `Lyrics`...)
            YTFilterChipsBarView(
                chips: contextualChips,
                selectedChip: appVM.selectedSearchChip,
                showExploreCompass: false
            ) { chip in
                appVM.selectedSearchChip = chip
                Task {
                    await appVM.executeSearch(query: chip == "All" ? query : "\(query) \(chip)")
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    if appVM.isSearching {
                        ForEach(0..<3, id: \.self) { _ in
                            YTVideoCardSkeletonView()
                        }
                    } else {
                        ForEach(appVM.searchResults) { video in
                            YTVideoCardView(video: video)
                        }
                    }
                }
                .padding(.bottom, appVM.currentVideo != nil ? 76 : 16)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showFiltersSheet) {
            YTSearchFiltersView()
        }
        .task {
            if appVM.searchResults.isEmpty || appVM.activeSubmittedQuery != query {
                await appVM.executeSearch(query: query)
            }
        }
    }
}

// MARK: - 3. Search Filters Screen (`GeneralBrowsing #30` & `Searching #05`)
public struct YTSearchFiltersView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header (`← Filters`)
            HStack(spacing: 16) {
                Button {
                    dismiss()
                    Task {
                        await appVM.executeSearch(query: appVM.activeSubmittedQuery)
                    }
                } label: {
                    YTIcon("yt_outline_arrow_left_24pt", fallback: "arrow.left", size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Text("Filters")
                    .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                    .foregroundStyle(YTTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(YTTheme.backgroundPrimary)

            // Grouped Cards on `#F1F1F1` background (`Sort by`, `Type`, `Upload date`)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    // Section 1: Sort by
                    filterGroupCard(title: "Sort by") {
                        ForEach(YTSearchFilters.SortBy.allCases, id: \.rawValue) { option in
                            filterOptionRow(
                                label: option.rawValue,
                                isSelected: appVM.searchFilters.sortBy == option
                            ) {
                                appVM.searchFilters.sortBy = option
                            }
                        }
                    }

                    // Section 2: Type
                    filterGroupCard(title: "Type") {
                        ForEach(YTSearchFilters.ContentType.allCases, id: \.rawValue) { option in
                            filterOptionRow(
                                label: option.rawValue,
                                isSelected: appVM.searchFilters.contentType == option
                            ) {
                                appVM.searchFilters.contentType = option
                            }
                        }
                    }

                    // Section 3: Upload date
                    filterGroupCard(title: "Upload date") {
                        ForEach(YTSearchFilters.UploadDate.allCases, id: \.rawValue) { option in
                            filterOptionRow(
                                label: option.rawValue,
                                isSelected: appVM.searchFilters.uploadDate == option
                            ) {
                                appVM.searchFilters.uploadDate = option
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(YTTheme.backgroundGrouped)
        }
    }

    private func filterGroupCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(YTTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            content()
        }
        .padding(.bottom, 8)
        .background(YTTheme.backgroundPrimary)
    }

    private func filterOptionRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(YTTheme.textPrimary)
                Spacer()
                if isSelected {
                    YTIcon("yt_outline_check_24pt", fallback: "checkmark", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
