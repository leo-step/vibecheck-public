import Foundation
import Supabase
import CoreLocation

// Parameters for your existing get_posts RPC
struct GetPostRPCParams: Encodable, Sendable {
    let viewer_id: UUID?
    let objectionable_bool: Bool
}

// Parameters for your new get_new_posts RPC
struct GetNewPostsRPCParams: Encodable, Sendable {
    let viewer_id: UUID?
    let objectionable_bool: Bool
    let last_seen: String
}

struct PostWithLikes: Decodable {
    let id: Int
    let likes: [String]?
}
  
func getAndUpdateLastLoginTime() -> Date? {
    let key = "lastLoginTime"
    let defaults = UserDefaults.standard

    // Retrieve previous login time
    let previousLoginTime = defaults.object(forKey: key) as? Date

    // Update with current time
    let currentTime = Date()
    defaults.set(currentTime, forKey: key)

    return previousLoginTime
}

enum PostFilter {
    case all
    case trending
    case friends // Not implemented yet
}

class EmojiPinViewModel: ObservableObject {
    @Published var emojiPins: [EmojiPin] = []
    @Published var filterObjectionableContent: Bool = false
    
    @Published var filteredEmojiPins: [EmojiPin] = []
    @Published var activeFilter: PostFilter = .all
    
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 5.0 // 5 seconds
    
    private var trendingUpdateTimer: Timer?
    private let trendingUpdateInterval: TimeInterval = 30.0 // Update trending status every 30 seconds
    
    init() {
        // Load saved filter setting
        self.filterObjectionableContent = UserDefaults.standard.bool(forKey: "filterObjectionableContent")
        
        // Initialize with empty arrays
        self.emojiPins = []
        self.filteredEmojiPins = []
        
        Task {
            await fetchEmojiPins()
        }
        startAutoRefresh()
        startTrendingUpdateTimer()
    }
    
    deinit {
        stopAutoRefresh()
        // Stop the trending update timer
        stopTrendingUpdateTimer()
    }
    
    func showAllPosts() {
        activeFilter = .all
        // No filtering - show all pins
        filteredEmojiPins = emojiPins
    }

    func showOnlyTrendingPosts() {
        activeFilter = .trending
        // Filter to show only trending pins
        filteredEmojiPins = emojiPins.filter { $0.isTrending }
    }
    
    func startTrendingUpdateTimer() {
        stopTrendingUpdateTimer()
        DispatchQueue.main.async {
            self.trendingUpdateTimer = Timer.scheduledTimer(withTimeInterval: self.trendingUpdateInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.calculateTrendingPosts()
            }
        }
    }

    func stopTrendingUpdateTimer() {
        trendingUpdateTimer?.invalidate()
        trendingUpdateTimer = nil
    }
    
    /// Update and persist the content filter
    func updateContentFilter(enabled: Bool) {
        self.filterObjectionableContent = enabled
        UserDefaults.standard.set(enabled, forKey: "filterObjectionableContent")
        
        Task {
            await fetchEmojiPins()
        }
    }
    
    /// Start automatic refresh timer
    func startAutoRefresh() {
        stopAutoRefresh()
        DispatchQueue.main.async {
            self.refreshTimer = Timer.scheduledTimer(withTimeInterval: self.refreshInterval, repeats: true) { [weak self] _ in
                Task { await self?.checkForNewPins() }
            }
        }
    }
    
    /// Stop automatic refresh timer
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    /// Fetch all posts via your existing RPC
    func fetchEmojiPins() async {
        do {
            struct Post: Codable {
                let id: Int
                let user_id: UUID
                let created_at: String
                let updated_at: String
                let emoji: String
                let comment: String
                let longitude: Double
                let latitude: Double
                let likes_count: Int
                let is_liked: Bool
            }
            
            let currentUserId = try? await supabase.auth.session.user.id
            let params = GetPostRPCParams(
                viewer_id: currentUserId,
                objectionable_bool: filterObjectionableContent
            )
//            let lastLoggedInResponse = try await supabase.rpc("get_user_last_signin").execute()
//            let lastLoginString: String? = lastLoggedInResponse.string()
            var lastLoginDate: Date? = getAndUpdateLastLoginTime()
            
//            if let ts = lastLoginString?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) {
//                let df = DateFormatter()
//                df.locale = Locale(identifier: "en_US_POSIX")
//                df.timeZone = TimeZone(secondsFromGMT: 0)
//                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSXXXXX"
//
//                if let date = df.date(from: ts) {
//                    lastLoginDate = date
//                } else {
//                    lastLoginDate = nil
//                }
//            }
            
            let response: PostgrestResponse<[Post]> = try await
                supabase.rpc("get_posts", params: params).execute()
            
            let posts = response.value
            guard !posts.isEmpty else {
              print("posts array is empty")
              return
            }
            
            // Sort by updated_at descending
            let sorted = posts.sorted {
                (parsePostgresTimestamp($0.updated_at) ?? .distantPast)
                  > (parsePostgresTimestamp($1.updated_at) ?? .distantPast)
            }
            
            // Assign zoom levels by quintile
            let total = sorted.count
            let quintileSize = max(1, total / 5)
            let pins = sorted.enumerated().map { idx, post -> EmojiPin in
                let quintile: Int = idx < quintileSize ? 0
                    : idx < quintileSize * 2 ? 1
                    : idx < quintileSize * 3 ? 2
                    : idx < quintileSize * 4 ? 3
                    : 4
                let zoomLevels = [15.5, 16.0, 16.5, 17.0, 17.5]
                let created = parsePostgresTimestamp(post.created_at) ?? Date()
                let updated = parsePostgresTimestamp(post.updated_at) ?? Date()
                let isMe = currentUserId != nil && post.user_id == currentUserId
                
                let isNew = (parsePostgresTimestamp(post.created_at) ?? Date.distantPast) > (lastLoginDate ?? Date.distantFuture) && !isMe
                print(post.comment, post.created_at, lastLoginDate, isNew)
                return EmojiPin(
                    id: post.id,
                    latitude: post.latitude,
                    longitude: post.longitude,
                    emoji: post.emoji,
                    comment: post.comment,
                    zoomLevel: zoomLevels[quintile],
                    createdAt: created,
                    updatedAt: updated,
                    upvotes: post.likes_count,
                    isLiked: post.is_liked,
                    isNew: isNew,
                    isTrending: false,
                    isCurrentUserPin: isMe
                )
            }
            
            DispatchQueue.main.async {
                self.emojiPins = pins
                // Calculate trending posts after setting emojiPins
                self.calculateTrendingPosts()
                // Apply current filter
                self.applyCurrentFilter()
            }
        } catch {
            print("Error fetching posts: \(error)")
        }
    }
    
    /// Check for new or updated posts since our last fetch
    func checkForNewPins() async {
        guard let mostRecent = getMostRecentPinDate() else {
            print("most recent pin updatedAt not found! doing another fetch for autorefresh...")
            await fetchEmojiPins()
            return
        }
        guard let lastSeenString = formatDateForQuery(mostRecent) else {
            print("❌ Couldn't format mostRecent for query")
            return
        }
        
        do {
            struct Post: Codable {
                let id: Int
                let user_id: UUID
                let created_at: String
                let updated_at: String
                let emoji: String
                let comment: String
                let longitude: Double
                let latitude: Double
                let likes_count: Int
                let is_liked: Bool
            }
            
            let currentUserId = try? await supabase.auth.session.user.id
            let params = GetNewPostsRPCParams(
                viewer_id: currentUserId,
                objectionable_bool: filterObjectionableContent,
                last_seen: lastSeenString
            )
            
//            let lastLoggedInResponse = try await supabase.rpc("get_user_last_signin").execute()
//            let lastLoginString: String? = lastLoggedInResponse.string()
            var lastLoginDate: Date? = getAndUpdateLastLoginTime()
            
//            if let ts = lastLoginString?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) {
//                let df = DateFormatter()
//                df.locale = Locale(identifier: "en_US_POSIX")
//                df.timeZone = TimeZone(secondsFromGMT: 0)
//                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSXXXXX"
//
//                if let date = df.date(from: ts) {
//                    lastLoginDate = date
//                } else {
//                    lastLoginDate = nil
//                }
//            }
            
            let response: PostgrestResponse<[Post]> = try await
                supabase.rpc("get_new_posts", params: params).execute()
            
            let posts = response.value
            guard !posts.isEmpty else {
              print("posts array is empty")
              return
            }
            print("🔄 Fetched \(posts.count) new/updated posts")
            
            var newPins = emojiPins
            for post in posts {
                let created = parsePostgresTimestamp(post.created_at) ?? Date()
                let updated = parsePostgresTimestamp(post.updated_at) ?? Date()
                let isMe = (currentUserId != nil && post.user_id == currentUserId)
                let isNew = (parsePostgresTimestamp(post.created_at) ?? Date.distantPast) > (lastLoginDate ?? Date.distantFuture) && !isMe
                print(post.comment, post.created_at, lastLoginDate, isNew)
                
                if let idx = newPins.firstIndex(where: { $0.id == post.id }) {
                    // update
                    newPins[idx].latitude         = post.latitude
                    newPins[idx].longitude        = post.longitude
                    newPins[idx].emoji            = post.emoji
                    newPins[idx].comment          = post.comment
                    newPins[idx].upvotes          = post.likes_count
                    newPins[idx].isLiked          = post.is_liked
                    newPins[idx].createdAt        = created
                    newPins[idx].updatedAt        = updated
                    newPins[idx].isCurrentUserPin = isMe
                } else {
                    // insert
                    let pin = EmojiPin(
                        id: post.id,
                        latitude: post.latitude,
                        longitude: post.longitude,
                        emoji: post.emoji,
                        comment: post.comment,
                        zoomLevel: 15.5,
                        createdAt: created,
                        updatedAt: updated,
                        upvotes: post.likes_count,
                        isLiked: post.is_liked,
                        isNew: isNew,
                        isCurrentUserPin: isMe
                    )
                    newPins.append(pin)
                }
            }
            
            DispatchQueue.main.async {
                self.emojiPins = newPins
                // Calculate trending posts after updating pins
                self.calculateTrendingPosts()
                // Apply current filter
                self.applyCurrentFilter()
            }
            
        } catch {
            print("Error checking for new posts: \(error)")
        }
    }
    
    /// Toggle like status for a specific pin
    func toggleLike(for pinId: Int) async {
        // Find the pin in our local collection
        guard let pinIndex = emojiPins.firstIndex(where: { $0.id == pinId }) else {
            print("Pin not found: \(pinId)")
            return
        }
        
        // Get current state
        let pin = emojiPins[pinIndex]
        let currentlyLiked = pin.isLiked
        
        // Update local state immediately for responsive UI
        DispatchQueue.main.async {
            self.emojiPins[pinIndex].isLiked = !currentlyLiked
            self.emojiPins[pinIndex].upvotes += currentlyLiked ? -1 : 1
            
            // Also update the filtered array to ensure UI consistency
            if let filteredIndex = self.filteredEmojiPins.firstIndex(where: { $0.id == pinId }) {
                self.filteredEmojiPins[filteredIndex].isLiked = !currentlyLiked
                self.filteredEmojiPins[filteredIndex].upvotes += currentlyLiked ? -1 : 1
            }
        }
        
        // Perform API call
        do {
            guard let userId = try? await supabase.auth.session.user.id else {
                print("User not authenticated")
                return
            }
            
            let params = LikeParams(post_id: pinId, user_id: userId)
            let function = currentlyLiked ? "remove_like" : "add_like"
            
            try await supabase
                .rpc(function, params: params)
                .execute()
            
            // Update trending posts after the API call succeeds
            DispatchQueue.main.async {
                self.calculateTrendingPosts()
                // Apply current filter
                self.applyCurrentFilter()
            }
            
            // If this is the user's own post, we should update the UserDefaults
            if pin.isCurrentUserPin {
                Task {
                    await updateSelfLikeInUserDefaults(for: pinId, isAdding: !currentlyLiked)
                }
            }
            
        } catch {
            print("Error toggling like: \(error)")
            
            // Revert local changes in case of error
            DispatchQueue.main.async {
                self.emojiPins[pinIndex].isLiked = currentlyLiked
                self.emojiPins[pinIndex].upvotes += currentlyLiked ? 1 : -1
                
                // Also revert in filtered array
                if let filteredIndex = self.filteredEmojiPins.firstIndex(where: { $0.id == pinId }) {
                    self.filteredEmojiPins[filteredIndex].isLiked = currentlyLiked
                    self.filteredEmojiPins[filteredIndex].upvotes += currentlyLiked ? 1 : -1
                }
                
                // Recalculate trending in case the temporary changes affected it
                self.calculateTrendingPosts()
                self.applyCurrentFilter()
            }
        }
    }
    
    /// Helper function to update UserDefaults when liking own post
    func updateSelfLikeInUserDefaults(for pinId: Int, isAdding: Bool) async {
        do {
            // Get current user
            guard let userId = try? await supabase.auth.session.user.id else {
                return
            }
            
            // Get current post likes count
            let userIdString = userId.uuidString
            let response: [PostWithLikes] = try await supabase
                .from("Posts")
                .select("id, likes")
                .eq("id", value: pinId)
                .execute()
                .value
            
            guard let post = response.first, let likes = post.likes else {
                return
            }
            
            // Filter out self-likes for tracking purposes
            let otherLikes = likes.filter { $0 != userIdString }
            let otherLikesCount = otherLikes.count
            
            // Update likes count for this post in UserDefaults
            var previousPostLikes = UserDefaults.standard.dictionary(forKey: "previousPostLikes") as? [String: Int] ?? [:]
            previousPostLikes[String(pinId)] = otherLikesCount
            UserDefaults.standard.set(previousPostLikes, forKey: "previousPostLikes")
            
            // Also update total likes count
            var totalLikesFromOthers = 0
            for (_, likeCount) in previousPostLikes {
                totalLikesFromOthers += likeCount
            }
            UserDefaults.standard.set(totalLikesFromOthers, forKey: "previousTotalLikes")
        } catch {
            print("Error updating self-like in UserDefaults: \(error)")
        }
    }
    
    // Add this helper function:
    private func applyCurrentFilter() {
        switch activeFilter {
        case .all:
            filteredEmojiPins = emojiPins
        case .trending:
            filteredEmojiPins = emojiPins.filter { $0.isTrending }
        case .friends:
            // Not implemented yet
            filteredEmojiPins = emojiPins
        }
    }
    
    /// Get the max updatedAt from local pins
    private func getMostRecentPinDate() -> Date? {
        guard !emojiPins.isEmpty else { return nil }
        return emojiPins.map(\.updatedAt).max()
    }
    
    /// Format `Date` for Postgres queries
    private func formatDateForQuery(_ date: Date) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
    
    /// Parse Postgres timestamp strings into `Date`
    private func parsePostgresTimestamp(_ ts: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        if let d = df.date(from: ts) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return df.date(from: ts)
    }
    
    /// Insert a new pin
    func addPin(
        latitude: Double,
        longitude: Double,
        emoji: String,
        comment: String,
        zoomLevel: Double,
        isCurrentUserPin: Bool = true
    ) async {
        guard let userId = try? await supabase.auth.session.user.id else {
            print("User not authenticated")
            return
        }
        struct NewPost: Codable {
            let user_id: UUID
            let emoji: String
            let comment: String
            let longitude: Double
            let latitude: Double
        }
        let newPost = NewPost(
            user_id: userId,
            emoji: emoji,
            comment: comment,
            longitude: longitude,
            latitude: latitude
        )
        do {
            _ = try await supabase.database
                .from("Posts")
                .insert(newPost)
                .execute()
            await fetchEmojiPins()
        } catch {
            print("Error inserting post: \(error)")
        }
    }
    func calculateTrendingPosts() {
        // Only process if we have enough posts to make a meaningful calculation
        if emojiPins.count > 5 {
            // Sort posts by like count in descending order
            let sortedByLikes = emojiPins.sorted { $0.upvotes > $1.upvotes }
            
            // Calculate the threshold for top 15%
            let thresholdIndex = max(0, Int(Double(sortedByLikes.count) * 0.15) - 1)
            let likeThreshold = thresholdIndex < sortedByLikes.count ? sortedByLikes[thresholdIndex].upvotes : 0
            
            // Only consider posts with at least 1 like as trending
            let minimumLikesForTrending = max(1, likeThreshold)
            
            // Update trending status for all pins
            for i in 0..<emojiPins.count {
                emojiPins[i].isTrending = emojiPins[i].upvotes >= minimumLikesForTrending && emojiPins[i].upvotes > 0
            }
        }
    }
}
