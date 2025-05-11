import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var emojiPinVM = EmojiPinViewModel()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var cameraState = MapCameraState()
    @StateObject private var onboardingManager = UserOnboardingManager()
    
    @State private var showingCommentSheet = false
    @State private var comment = ""
    @State private var selectedEmoji = "💬"
    @State private var showingEULA = false
    @State private var showingActivityPopup = false
    
    
    @State private var newLikesCount: Int = 0
    @State private var lastOpenedTimestamp: Date = UserDefaults.standard.object(forKey: "lastCheckedLikes") as? Date ?? Date()
    @State private var likesCheckTimer: Timer?
    
    @State private var showingFilterMenu = false
    @State private var currentFilter: PostFilter = .all
    
    
    private func updateLastViewedTimestamp() {
        Task<Void, Never> {
            do {
                if let currentUser = try? await supabase.auth.session.user {
                    // Format current date
                    let formatter = ISO8601DateFormatter()
                    let currentTimeString = formatter.string(from: Date())
                    
                    // Convert the UUID to string
                    let userIdString = currentUser.id.uuidString
                    
                    // Try to update or insert with string values
                    try await supabase
                        .from("Activity")
                        .upsert([
                            "user_id": userIdString,
                            "last_viewed_at": currentTimeString
                        ])
                        .execute()
                }
            } catch {
                print("Error updating activity timestamp: \(error)")
            }
        }
    }
    
    private func checkForNewLikes() {
        Task {
            do {
                if let currentUser = try? await supabase.auth.session.user {
                    let userId = currentUser.id
                    let userIdString = userId.uuidString
                    
                    print("DEBUG: ---- STARTING LIKES CHECK ----")
                    
                    // Get all posts by this user that have likes
                    let response: [PostWithLikes] = try await supabase
                        .from("Posts")
                        .select("id, likes, created_at")
                        .eq("user_id", value: userId)
                        .execute()
                        .value
                    
                    // Count total likes from others across all posts
                    var totalLikesFromOthers = 0
                    var postsWithLikeCounts: [Int: Int] = [:] // Store postId: likeCount pairs
                    
                    for post in response {
                        if let likes = post.likes {
                            // Filter out self-likes
                            let otherLikes = likes.filter { $0 != userIdString }
                            totalLikesFromOthers += otherLikes.count
                            
                            // Store the like count for this post
                            if otherLikes.count > 0 {
                                postsWithLikeCounts[post.id] = otherLikes.count
                            }
                            
                            print("DEBUG: Post \(post.id) has \(otherLikes.count) likes from others")
                        }
                    }
                    
                    print("DEBUG: Total likes from others: \(totalLikesFromOthers)")
                    
                    // Get the previously seen total likes
                    let previousTotalLikes = UserDefaults.standard.integer(forKey: "previousTotalLikes")
                    print("DEBUG: Previous total likes: \(previousTotalLikes)")
                    
                    // Get previously seen post/like counts
                    let previousPostLikes = UserDefaults.standard.dictionary(forKey: "previousPostLikes") as? [String: Int] ?? [:]
                    
                    // Check for changes in individual posts' like counts
                    var newNotifications = 0
                    var postsWithNewLikes: [Int] = []
                    
                    for (postId, likeCount) in postsWithLikeCounts {
                        let previousCount = previousPostLikes[String(postId)] ?? 0
                        if likeCount > previousCount {
                            // This post has new likes
                            newNotifications += 1
                            postsWithNewLikes.append(postId)
                        }
                    }
                    
                    // Save the updated post/like counts
                    var updatedPostLikes: [String: Int] = [:]
                    for (postId, likeCount) in postsWithLikeCounts {
                        updatedPostLikes[String(postId)] = likeCount
                    }
                    
                    // Calculate new likes
                    let newLikes = max(newNotifications, totalLikesFromOthers > previousTotalLikes ? totalLikesFromOthers - previousTotalLikes : 0)
                    print("DEBUG: New likes to show: \(newLikes)")
                    
                    // Update on main thread
                    DispatchQueue.main.async {
                        self.newLikesCount = newLikes
                    }
                    
                    // Store posts with new likes
                    UserDefaults.standard.set(postsWithNewLikes, forKey: "postsWithNewLikes")
                }
            } catch {
                print("Error fetching posts with likes: \(error)")
            }
        }
    }
    
    func navigateToPost(latitude: Double, longitude: Double, zoomLevel: Double) {
        showingActivityPopup = false
        
        // Create a coordinate from the post's latitude and longitude
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        
        // Use the cameraState to move to the post location
        cameraState.centerToLocation(coordinate, zoomLevel: zoomLevel)
    }
    
    // Update PostWithLikes struct to include created_at
    struct PostWithLikes: Decodable {
        let id: Int
        let likes: [String]?
        let created_at: String?
    }
    
    enum PostFilter {
        case all
        case trending
        case friends // Not implemented yet
    }

    // Function to apply the selected filter
    func applyFilter(_ filter: PostFilter) {
        switch filter {
        case .all:
            // Show all posts - reset any filtering
            emojiPinVM.showAllPosts()
        case .trending:
            // Show only trending posts
            emojiPinVM.showOnlyTrendingPosts()
        case .friends:
            // Not implemented yet
            break
        }
    }

    // Create a new FilterMenuView
    struct FilterMenuView: View {
        @Binding var currentFilter: PostFilter
        var onFilterSelected: (PostFilter) -> Void
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    onFilterSelected(.all)
                }) {
                    HStack {
                        Text("All")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if currentFilter == .all {
                            Image(systemName: "checkmark")
                                .foregroundColor(.customPink)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                
                Divider()
                
                Button(action: {
                    onFilterSelected(.trending)
                }) {
                    HStack {
                        Text("VIBIN Posts")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if currentFilter == .trending {
                            Image(systemName: "checkmark")
                                .foregroundColor(.customPink)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                
                Divider()
                
                // "Friends" option (disabled)
                HStack {
                    Text("Friends")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                    
                    Text("coming soon")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .padding(.leading, 4)
                    
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .background(Color.clear) // Not clickable
            }
            .frame(width: 200)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 5)
        }
    }
    
    var body: some View {
        return NavigationStack {
            ZStack {
                // Map view
                MapViewRepresentable(
                    userLocation: $locationManager.userLocation,
                    emojiPins: emojiPinVM.filteredEmojiPins,
                    cameraState: cameraState,
                    viewModel: emojiPinVM
                )
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    if showingFilterMenu {
                        showingFilterMenu = false
                    }
                }
                
                // Refocus button (bottom left, only when needed)
                if !cameraState.isUserLocationVisible {
                    VStack {
                        Spacer()
                        HStack {
                            Button(action: {
                                cameraState.centerToUserLocation(locationManager.userLocation)
                            }) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.darkGray.opacity(0.9)))
                                    .shadow(radius: 2)
                            }
                            .padding(.leading, 20)
                            .padding(.bottom, 30)
                            .transition(.opacity)
                            .animation(.easeInOut, value: cameraState.isUserLocationVisible)
                            
                            Spacer()
                        }
                    }
                }
                
                // Plus button for adding a new pin
                VStack {
                    Spacer()
                    Button(action: {
                        showingCommentSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.customPink))
                            .shadow(radius: 4)
                    }
                    .padding(.bottom, 30)
                }
            }
            .toolbar {
                // Add the Activity button with notification badge to the leading position
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        Task {
                            do {
                                if let currentUser = try? await supabase.auth.session.user {
                                    let userId = currentUser.id
                                    let userIdString = userId.uuidString
                                    
                                    // Get all posts by this user that have likes
                                    let response: [PostWithLikes] = try await supabase
                                        .from("Posts")
                                        .select("id, likes")
                                        .eq("user_id", value: userId)
                                        .execute()
                                        .value
                                    
                                    // Count total likes from others
                                    var totalLikesFromOthers = 0
                                    var updatedPostLikes: [String: Int] = [:]
                                    
                                    for post in response {
                                        if let likes = post.likes {
                                            // Filter out self-likes
                                            let otherLikes = likes.filter { $0 != userIdString }
                                            totalLikesFromOthers += otherLikes.count
                                            
                                            // Store the like count for this post
                                            if otherLikes.count > 0 {
                                                updatedPostLikes[String(post.id)] = otherLikes.count
                                            }
                                        }
                                    }
                                    
                                    // Save the current total likes count
                                    UserDefaults.standard.set(totalLikesFromOthers, forKey: "previousTotalLikes")
                                    UserDefaults.standard.set(updatedPostLikes, forKey: "previousPostLikes")
                                    print("DEBUG: Updated previous total likes to: \(totalLikesFromOthers)")
                                    
                                    // Reset the notification counter
                                    DispatchQueue.main.async {
                                        self.newLikesCount = 0
                                    }
                                    // Clear posts with new likes
                                    UserDefaults.standard.set([], forKey: "postsWithNewLikes")
                                }
                            } catch {
                                print("Error updating like notification count: \(error)")
                            }
                        }
                        
                        // Show the activity popup
                        showingActivityPopup = true
                        
                    }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "heart")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.darkGray)
                            
                            // Only show the badge if there are new likes
                            if newLikesCount > 0 {
                                ZStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 18, height: 18)
                                    
                                    Text("\(newLikesCount)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .offset(x: 10, y: -10)
                            }
                        }
                    }
                }
                
                // Add the new Filter button in the middle
                ToolbarItem(placement: .principal) {
                    Button(action: {
                        showingFilterMenu.toggle() // Toggle the filter menu visibility
                    }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.darkGray)
                    }
                }
                
                // Keep the profile button on the trailing position
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ProfileView().environmentObject(emojiPinVM)) {
                        Image(systemName: "person.circle")
                            .foregroundColor(.darkGray)
                    }
                }
            }
            .sheet(isPresented: $showingCommentSheet, onDismiss: {
                // Reset the comment text when the sheet is dismissed without submitting
                comment = ""
                // Reset the emoji to the default as well
                selectedEmoji = "💬"
            }) {
                EnhancedCommentInputView(
                    comment: $comment,
                    selectedEmoji: $selectedEmoji,
                    isPresented: $showingCommentSheet
                ) { submittedComment, emoji in
                    if !submittedComment.isEmpty {
                        if let location = locationManager.userLocation {
                            Task {
                                await emojiPinVM.addPin(
                                    latitude: location.coordinate.latitude,
                                    longitude: location.coordinate.longitude,
                                    emoji: selectedEmoji,
                                    comment: submittedComment,
                                    zoomLevel: 18,
                                    isCurrentUserPin: true
                                )
                            }
                        }
                    }
                    comment = "" // Reset the comment field
                }
            }
            // Add overlay for filter menu
            .overlay(alignment: .top) {
                if showingFilterMenu {
                    VStack(spacing: 0) {
                        // Small spacer to push menu below the toolbar
                        Spacer().frame(height: 5)
                        
                        FilterMenuView(
                            currentFilter: $currentFilter,
                            onFilterSelected: { filter in
                                currentFilter = filter
                                showingFilterMenu = false
                                applyFilter(filter)
                            }
                        )
                    }
                    .animation(.easeInOut(duration: 0.2), value: showingFilterMenu)
                    .transition(.opacity)
                }
            }
            .overlay {
                if showingActivityPopup {
                    ActivityPopupView(
                        isPresented: $showingActivityPopup,
                        onPostTap: { post in
                            // Close the popup
                            showingActivityPopup = false
                            
                            // Navigate to the post location
                            let coordinate = CLLocationCoordinate2D(
                                latitude: post.latitude,
                                longitude: post.longitude
                            )
                            cameraState.centerToLocation(coordinate, zoomLevel: post.zoomLevel)
                        }
                    )
                }
            }
            .environmentObject(emojiPinVM)
            
            // Use fullScreenCover for the EULA to ensure the user must interact with it
            .fullScreenCover(isPresented: $showingEULA) {
                EULAView(isPresented: $showingEULA, hasAgreed: Binding(
                    get: { onboardingManager.hasAgreedToEULA },
                    set: { newValue in
                        if newValue {
                            onboardingManager.userAgreedToEULA()
                        }
                    }
                ))
            }
            .onAppear {
                // Check if we need to show the EULA
                checkAndShowEULA()
                // Initialize the last notification count if it doesn't exist
                if UserDefaults.standard.object(forKey: "lastLikeNotificationCount") == nil {
                    // Save a default value of 0
                    UserDefaults.standard.set(0, forKey: "lastLikeNotificationCount")
                }
                
                 checkForNewLikes()
                
                // Set up a timer to periodically check for new likes (every 10 seconds)
                 likesCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
                     checkForNewLikes()
                }
                
            }
            .onChange(of: locationManager.authorizationStatus) { newValue in
                // When location permission status changes, check if we need to show EULA
                checkAndShowEULA()
            }
            .onDisappear {
                // Invalidate the timer when the view disappears
                likesCheckTimer?.invalidate()
            }
        }
        
        func checkAndShowEULA() {
            // Only show EULA if:
            // 1. User has responded to location permissions (not .notDetermined)
            // 2. User hasn't already agreed to EULA
            if locationManager.authorizationStatus != .notDetermined && !onboardingManager.hasAgreedToEULA {
                // Small delay to ensure location dialog is fully dismissed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingEULA = true
                }
            }
        }
        
        struct EnhancedCommentInputView: View {
            @Binding var comment: String
            @Binding var selectedEmoji: String
            @Binding var isPresented: Bool
            @State private var showingEmojiPicker = false
            @State private var selectedCategory = "Smileys"  // Default to Smileys since they're popular
            
            // Function to dismiss the keyboard
            private func dismissKeyboard() {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            
            // Track recently used emojis and keep original options
            @State private var displayedEmojis: [String] = []
            let originalEmojiOptions = ["🥴", "😂", "💔", "💀", "🔥"]
            let maxVisibleEmojis = 5  // Maximum number of emoji options to show (excluding + button)
            
            var onSubmit: (String, String) -> Void
            
            // Emoji categories (matching the bottom row in screenshot)
            let categories = ["Smileys", "People", "Animals", "Food", "Activities", "Travel", "Objects", "Symbols"]
            
            // Emoji collections by category
            let emojisByCategory: [String: [String]] = [
                "Smileys": [
                    "😀", "😃", "😄", "😁", "😆", "🥹", "😅", "😂", "🤣", "😍", "😌", "😉", "🙃", "🙂", "😇",
                    "😊", "☺️", "🥲", "🥰", "😘", "😗", "😙", "😚", "😋", "😛", "😝", "😜", "😏", "🥳", "🤩",
                    "🥸", "😎", "🤓", "🧐", "🤨", "🤪", "😒", "😞", "😔", "😟", "😕", "🙁", "☹️", "😣", "😖",
                    "🤬", "😡", "😠", "😤", "😭", "😢", "🥺", "😩", "😫", "🤯", "😳", "🥵", "🥶", "😶‍🌫️", "😱",
                    "😨", "😰", "😥", "🫠", "🤫", "🫡", "🫢", "🤭", "🫣", "🤔", "🤗", "😓", "🤥", "😶", "🫥",
                    "😐", "🫤", "😑", "😬", "🙄", "😯", "😮‍💨", "😪", "🤤", "😴", "🥱", "😲", "😮", "😧", "😦",
                    "😵", "😵‍💫", "🤐", "🥴", "🤢", "🤮", "🤧", "😷", "🤒", "💩", "🤡", "👺", "👹", "👿", "😈",
                    "🤠", "🤑", "🤕", "👻", "💀", "☠️"
                ],
                "People": [
                    "👶", "👧", "🧒", "👦", "👩", "🧑", "👨", "👵", "🧓", "👴", "👲", "👳‍♀️", "👳‍♂️", "🧕",
                    "👮‍♀️", "👮‍♂️", "👷‍♀️", "👷‍♂️", "💂‍♀️", "💂‍♂️", "🕵️‍♀️", "🕵️‍♂️", "👩‍⚕️", "🧑‍⚕️", "👨‍⚕️",
                    "👩‍🌾", "🧑‍🌾", "👨‍🌾", "👩‍🍳", "🧑‍🍳", "👨‍🍳", "👩‍🎓", "🧑‍🎓", "👨‍🎓", "👩‍🏫", "🧑‍🏫",
                    "👨‍🏫", "👩‍💻", "🧑‍💻", "👨‍💻", "👩‍💼", "🧑‍💼", "👨‍💼", "👩‍🔧", "🧑‍🔧", "👨‍🔧", "👩‍🏭",
                    "🧑‍🏭", "👨‍🏭", "👩‍🎤", "🧑‍🎤", "👨‍🎤", "👩‍🎨", "🧑‍🎨", "👨‍🎨", "👩‍🔬", "🧑‍🔬", "👨‍🔬",
                    "👩‍🚒", "🧑‍🚒", "👨‍🚒", "👩‍✈️", "🧑‍✈️", "👨‍✈️", "👩‍🚀", "🧑‍🚀", "👨‍🚀", "👩‍⚖️", "🧑‍⚖️",
                    "👨‍⚖️", "👰‍♀️", "👰", "👰‍♂️", "🤵‍♀️", "🤵", "🤵‍♂️", "👸", "🫅", "🤴", "🥷", "🦸‍♀️", "🦸",
                    "🦸‍♂️", "🦹‍♀️", "🦹", "🦹‍♂️", "🧙‍♀️", "🧙", "🧙‍♂️", "🧝‍♀️", "🧝", "🧝‍♂️", "🧌", "🧛‍♀️", "🧛",
                    "🧛‍♂️", "🧟‍♀️", "🧟", "🧟‍♂️", "🧞‍♀️", "🧞", "🧞‍♂️", "🧜‍♀️", "🧜", "🧜‍♂️", "🧚‍♀️", "🧚", "🧚‍♂️",
                    "👼", "🤰", "🫄", "🫃", "🤱", "👩‍🍼", "🧑‍🍼", "👨‍🍼", "🙇‍♀️", "🙇", "🙇‍♂️", "💁‍♀️", "💁",
                    "💁‍♂️", "🙅‍♀️", "🙅", "🙅‍♂️", "🙆‍♀️", "🙆", "🙆‍♂️", "🙋‍♀️", "🙋", "🙋‍♂️", "🧏‍♀️", "🧏",
                    "🧏‍♂️", "🤦‍♀️", "🤦", "🤦‍♂️", "🤷‍♀️", "🤷", "🤷‍♂️", "🙍‍♀️", "🙍", "🙍‍♂️", "🙎‍♀️", "🙎",
                    "🙎‍♂️", "💇‍♀️", "💇", "💇‍♂️", "💆‍♀️", "💆", "💆‍♂️", "🧖‍♀️", "🧖", "🧖‍♂️", "💅", "🤳",
                    "💃", "🕺", "👯‍♀️", "👯", "👯‍♂️", "👩‍🦽", "🧑‍🦽", "👨‍🦽", "👩‍🦼", "🧑‍🦼", "👨‍🦼", "🚶‍♀️",
                    "🚶", "🚶‍♂️", "👩‍🦯", "🧑‍🦯", "👨‍🦯", "🧎‍♀️", "🧎", "🧎‍♂️", "🏃‍♀️", "🏃", "🏃‍♂️", "🧍‍♀️",
                    "🧍", "🧍‍♂️", "👭", "👫", "👬", "👩‍❤️‍👨", "👩‍❤️‍👩", "💑", "👨‍❤️‍👨", "👩‍❤️‍💋‍👨", "👩‍❤️‍💋‍👩",
                    "💏", "👨‍❤️‍💋‍👨", "👨‍👩‍👦", "👨‍👩‍👧", "👨‍👩‍👧‍👦", "👨‍👩‍👦‍👦", "👨‍👩‍👧‍👧", "👩‍👩‍👦", "👩‍👩‍👧",
                    "👩‍👩‍👧‍👦", "👩‍👩‍👦‍👦", "👩‍👩‍👧‍👧", "👨‍👨‍👦", "👨‍👨‍👧", "👨‍👨‍👧‍👦", "👨‍👨‍👦‍👦", "👨‍👨‍👧‍👧",
                    "👩‍👦", "👩‍👧", "👩‍👧‍👦", "👩‍👦‍👦", "👩‍👧‍👧", "👨‍👦", "👨‍👧", "👨‍👧‍👦", "👨‍👦‍👦", "👨‍👧‍👧",
                    "🧶", "🧵", "🪡", "🧥", "🥼", "🦺", "👚", "👕", "👖", "🩲", "🩳", "👔", "👗", "👘", "🥻",
                    "🩱", "👙", "🩴", "🥿", "👠", "👡", "👢", "👞", "👟", "🥾", "🧣", "🧤", "🧦", "👒", "🧢",
                    "🎩", "🎓", "⛑", "🪖", "👑", "💍", "👝", "👛", "👜", "💼", "🎒", "🧳", "🕶", "🥽", "👓",
                    "🌂"
                ],
                "Animals": [
                    "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐻‍❄️", "🐨", "🐯", "🦁", "🐮", "🐷",
                    "🐽", "🐸", "🐵", "🙈", "🙉", "🙊", "🐒", "🐔", "🐧", "🐦", "🐤", "🐣", "🐥", "🦆", "🦅",
                    "🦉", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🪱", "🐛", "🦋", "🐌", "🐞", "🐜", "🪰", "🪲",
                    "🪳", "🦟", "🦗", "🕷", "🕸", "🦂", "🐢", "🐍", "🦎", "🦖", "🦕", "🐙", "🦑", "🦐", "🦞",
                    "🦀", "🐡", "🐠", "🐟", "🐬", "🐳", "🐋", "🦈", "🦭", "🐊", "🐅", "🐆", "🦓", "🦍", "🦧",
                    "🦣", "🐘", "🦛", "🦏", "🐪", "🐫", "🦒", "🦘", "🦬", "🐃", "🐂", "🐄", "🐎", "🐖", "🐏",
                    "🐑", "🦙", "🐐", "🦌", "🐕", "🐩", "🦮", "🐕‍🦺", "🐈", "🐈‍⬛", "🪶", "🐓", "🦃", "🦤", "🦚",
                    "🦜", "🦢", "🦩", "🕊", "🐇", "🦝", "🦨", "🦡", "🦫", "🦦", "🦥", "🐁", "🐀", "🐿", "🦔",
                    "🐉", "🐲", "🌵", "🎄", "🌲", "🌳", "🌴", "🪵", "🌱", "🌿", "☘️", "🍀", "🎍", "🪴", "🎋",
                    "🍃", "🍂", "🍁", "🪺", "🪹", "🪨", "🪸", "🍄", "🐚", "🌾", "💐", "🌷", "🌹", "🥀", "🪷",
                    "🌺", "🌸", "🌼", "🌻"
                ],
                "Food": [
                    "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝",
                    "🍅", "🍆", "🥑", "🥦", "🥬", "🥒", "🌶", "🫑", "🌽", "🥕", "🥔", "🧄", "🧅", "🥐", "🥯",
                    "🍞", "🥖", "🥨", "🧀", "🥚", "🧈", "🥞", "🧇", "🥓", "🥩", "🍗", "🍖", "🦴", "🌭", "🍔",
                    "🍟", "🍕", "🫓", "🥪", "🥙", "🧆", "🌮", "🌯", "🫔", "🥗", "🥘", "🫕", "🥫", "🍝", "🍜",
                    "🍲", "🍛", "🍣", "🍱", "🥟", "🦪", "🍤", "🍙", "🍚", "🍘", "🍥", "🥠", "🥮", "🍢", "🍡",
                    "🍧", "🍨", "🍦", "🥧", "🧁", "🍰", "🎂", "🍮", "🍭", "🍬", "🍫", "🍿", "🍩", "🍪", "🌰",
                    "🥜", "🫘", "🍯", "🥛", "🫗", "🍼", "☕️", "🫖", "🍵", "🧋", "🥤", "🧃", "🧉", "🧊", "🥢",
                    "🍽", "🍴", "🥄", "🥡", "🥣", "🧂"
                ],
                "Activities": [
                    "⚽️", "🏀", "🏈", "⚾️", "🥎", "🎾", "🏐", "🏉", "🥏", "🎱", "🪀", "🏓", "🏸", "🏒", "🏑",
                    "🥍", "🏏", "🪃", "⛳️", "🪁", "🏹", "🎣", "🤿", "🥊", "🥋", "🎽", "🛹", "🛼", "🛷", "⛸",
                    "🥌", "🎿", "⛷", "🏂", "🪂", "🏋️‍♀️", "🏋️", "🏋️‍♂️", "🤼‍♀️", "🤼", "🤼‍♂️", "🤸‍♀️", "🤸",
                    "🤸‍♂️", "⛹️‍♀️", "⛹️", "⛹️‍♂️", "🤺", "🤾‍♀️", "🤾", "🤾‍♂️", "🏌️‍♀️", "🏌️", "🏌️‍♂️", "🏇", "🧘‍♀️",
                    "🧘", "🧘‍♂️", "🏄‍♀️", "🏄", "🏄‍♂️", "🏊‍♀️", "🏊", "🏊‍♂️", "🤽‍♀️", "🤽", "🤽‍♂️", "🚣‍♀️", "🚣",
                    "🚣‍♂️", "🧗‍♀️", "🧗", "🧗‍♂️", "🚵‍♀️", "🚵", "🚵‍♂️", "🚴‍♀️", "🚴", "🚴‍♂️", "🏆", "🥇", "🥈",
                    "🥉", "🏅", "🎖", "🏵", "🎗", "🎫", "🎟", "🎪", "🤹‍♀️", "🤹", "🤹‍♂️", "🎭", "🩰", "🎨",
                    "🎬", "🎤", "🎧", "🎼", "🎹", "🥁", "🪘", "🎷", "🎺", "🪗", "🎸", "🪕", "🎻", "🎲", "♟",
                    "🎯", "🎳", "🎮", "🎰", "🧩"
                ],
                "Travel": [
                    "🚗", "🚕", "🚙", "🚌", "🚎", "🏎", "🚓", "🚑", "🚒", "🚐", "🚚", "🚛", "🚜", "🛴", "🚲",
                    "🛵", "🏍", "🛺", "🚨", "🚔", "🚍", "🚘", "🚖", "🚡", "🚠", "🚟", "🚃", "🚋", "🚞", "🚝",
                    "🚄", "🚅", "🚈", "🚂", "🚆", "🚇", "🚊", "🚉", "✈️", "🛫", "🛬", "🛩", "💺", "🛰", "🚀",
                    "🛸", "🚁", "⛵️", "🛶", "🚤", "🛥", "🛳", "🚢", "⛴", "🛟", "⚓️", "🪝", "⛽️", "🚧", "🚦",
                    "🚥", "🚏", "🗺", "🗿", "🗽", "🗼", "🏰", "🏯", "🏟", "🎡", "🎢", "🎠", "⛲️", "⛱", "🏖",
                    "🏝", "🏜", "🌋", "⛰", "🏔", "🗻", "🏕", "⛺️", "🛖", "🏠", "🏡", "🏘", "🏚", "🏗", "🏭",
                    "🏢", "🏬", "🏣", "🏤", "🏥", "🏦", "🏨", "🏪", "🏫", "🏩", "💒", "🏛", "⛪️", "🕌", "🕍",
                    "🛕", "🕋", "⛩", "🛤", "🛣", "🗾", "🎑", "🏞", "🌅", "🌄", "🌠", "🎇", "🎆", "🌇", "🌆",
                    "🏙", "🌃", "🌌", "🌉", "🌁", "🌚", "🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘", "🌜",
                    "🌛", "🌙", "🌞", "🌝", "🌎", "🌍", "🌏", "🪐", "💫", "⭐️", "🌟", "✨", "⚡️", "☄️", "💥",
                    "🔥", "🌪", "🌈", "☀️", "🌤", "⛅️", "🌥", "☁️", "🌦", "🌧", "⛈", "🌩", "🌨", "❄️", "☃️",
                    "⛄️", "🌬", "💨", "💧", "💦", "🫧", "☔️", "☂️", "🌊"
                ],
                "Objects": [
                    "⌚️", "📱", "📲", "💻", "⌨️", "🖥", "🖨", "🖱", "🖲", "🕹", "🗜", "💽", "💾", "💿", "📀",
                    "📼", "📷", "📸", "📹", "🎥", "📽", "🎞", "📞", "☎️", "📟", "📠", "📺", "📻", "🎙", "🎚",
                    "🎛", "⏱", "⏲", "⏰", "🕰", "⏳", "⌛️", "📡", "🔋", "🪫", "🔌", "💡", "🔦", "🕯", "🪔",
                    "🧯", "🛢", "💵", "💴", "💶", "💷", "🪙", "💰", "💳", "💎", "⚖️", "🪜", "🧰", "🪛", "🔧",
                    "🔨", "⚒", "🛠", "⛏", "🪚", "🔩", "⚙️", "🧱", "⛓", "🧲", "🔫", "💣", "🧨", "🪓", "🔪",
                    "🗡", "⚔️", "🛡", "🚬", "⚰️", "🪦", "⚱️", "🏺", "🔮", "📿", "🧿", "💈", "⚗️", "🔭", "🔬",
                    "🕳", "🩻", "🩹", "🩺", "💊", "💉", "🩸", "🧬", "🦠", "🧫", "🧪", "🌡", "🧹", "🪠", "🧺",
                    "🧻", "🚽", "🚰", "🚿", "🛁", "🛀", "🧼", "🪥", "🪒", "🧽", "🪣", "🧴", "🛎", "🔑", "🗝",
                    "🚪", "🪑", "🛋", "🛏", "🛌", "🧸", "🪆", "🖼", "🪞", "🪟", "🛍", "🛒", "🎁", "🎈", "🎏",
                    "🎀", "🪄", "🪅", "🎊", "🎉", "🎎", "🏮", "🎐", "🪩", "🧧", "✉️", "📩", "📨", "📧", "💌",
                    "📥", "📤", "📦", "🏷", "🪧", "📪", "📫", "📬", "📭", "📮", "📯", "📜", "📃", "📄", "📑",
                    "🧾", "📊", "📈", "📉", "🗒", "🗓", "📆", "📅", "🗑", "📇", "🗃", "🗳", "🗄", "📋", "📁",
                    "📂", "🗂", "🗞", "📰", "📓", "📔", "📒", "📕", "📗", "📘", "📙", "📚", "📖", "🔖", "🧷",
                    "🔗", "📎", "🖇", "📐", "📏", "🧮", "📌", "📍", "✂️", "🖊", "🖋", "✒️", "🖌", "🖍", "✏️",
                    "🔍", "🔎", "🔏", "🔐", "🔒", "🔓"
                ],
                "Symbols": [
                    "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❤️‍🔥", "❤️‍🩹", "❣️", "💕",
                    "💞", "💓", "💗", "💖", "💘", "💝", "💟", "☮️", "✝️", "☪️", "🕉", "☸️", "✡️", "🔯", "🕎",
                    "☯️", "☦️", "🛐", "⛎", "♈️", "♉️", "♊️", "♋️", "♌️", "♍️", "♎️", "♏️", "♐️", "♑️", "♒️",
                    "♓️", "🆔", "⚛️", "🉑", "☢️", "☣️", "📴", "📳", "🈶", "🈚️", "🈸", "🈺", "🈷️", "✴️", "🆚",
                    "💮", "🉐", "㊙️", "㊗️", "🈴", "🈵", "🈹", "🈲", "🅰️", "🅱️", "🆎", "🆑", "🅾️", "🆘", "❌",
                    "⭕️", "🛑", "⛔️", "📛", "🚫", "💯", "💢", "♨️", "🚷", "🚯", "🚳", "🚱", "🔞", "📵", "🚭",
                    "❗️", "❕", "❓", "❔", "‼️", "⁉️", "🔅", "🔆", "〽️", "⚠️", "🚸", "🔱", "⚜️", "🔰", "♻️",
                    "✅", "🈯️", "💹", "❇️", "✳️", "❎", "🌐", "💠", "Ⓜ️", "🌀", "💤", "🏧", "🚾", "♿️", "🅿️",
                    "🛗", "🈳", "🈂️", "🛂", "🛃", "🛄", "🛅", "🚹", "🚺", "🚼", "⚧", "🚻", "🚮", "🎦", "📶",
                    "🈁", "🔣", "ℹ️", "🔤", "🔡", "🔠", "🆖", "🆗", "🆙", "🆒", "🆕", "🆓", "0️⃣", "1️⃣", "2️⃣",
                    "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣", "🔟", "🔢", "#️⃣", "*️⃣", "⏏️", "▶️", "⏸", "⏯",
                    "⏹", "⏺", "⏭", "⏮", "⏩", "⏪", "⏫", "⏬", "◀️", "🔼", "🔽", "➡️", "⬅️", "⬆️", "⬇️", "↗️",
                    "↘️", "↙️", "↖️", "↕️", "↔️", "↪️", "↩️", "⤴️", "⤵️", "🔀", "🔁", "🔂", "🔄", "🔃", "🎵",
                    "🎶", "➕", "➖", "➗", "✖️", "🟰", "♾️", "💲", "💱", "™️", "©️", "®️", "👁‍🗨", "🔚", "🔙", "🔛",
                    "🔝", "🔜", "〰️", "➰", "➿", "✔️", "☑️", "🔘", "🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "⚫️",
                    "⚪️", "🟤", "🔺", "🔻", "🔸", "🔹", "🔶", "🔷", "🔳", "🔲", "▪️", "▫️", "◾️", "◽️", "◼️",
                    "◻️", "🟥", "🟧", "🟨", "🟩", "🟦", "🟪", "🟫", "⬛️", "⬜️", "🔈", "🔇", "🔉", "🔊", "🔔",
                    "🔕", "📣", "📢", "💬", "💭", "🗯", "♠️", "♣️", "♥️", "♦️", "🃏", "🎴", "🀄️", "🕐", "🕑",
                    "🕒", "🕓", "🕔", "🕕", "🕖", "🕗", "🕘", "🕙", "🕚", "🕛", "🕜", "🕝", "🕞", "🕟", "🕠",
                    "🕡", "🕢", "🕣", "🕤", "🕥", "🕦", "🕧", "🏳️", "🏴", "🏁", "🚩", "🏳️‍🌈", "🏳️‍⚧️", "🏴‍☠️",
                    "🇦🇨", "🇦🇩", "🇦🇪", "🇦🇫", "🇦🇬", "🇦🇮", "🇦🇱", "🇦🇲", "🇦🇴", "🇦🇶", "🇦🇷", "🇦🇸",
                    "🇦🇹", "🇦🇺", "🇦🇼", "🇦🇽", "🇦🇿", "🇧🇦", "🇧🇧", "🇧🇩", "🇧🇪", "🇧🇫", "🇧🇬", "🇧🇭",
                    "🇧🇮", "🇧🇯", "🇧🇱", "🇧🇲", "🇧🇳", "🇧🇴", "🇧🇶", "🇧🇷", "🇧🇸", "🇧🇹", "🇧🇻", "🇧🇼",
                    "🇧🇾", "🇧🇿", "🇨🇦", "🇨🇨", "🇨🇩", "🇨🇫", "🇨🇬", "🇨🇭", "🇨🇮", "🇨🇰", "🇨🇱", "🇨🇲",
                    "🇨🇳", "🇨🇴", "🇨🇵", "🇨🇷", "🇨🇺", "🇨🇻", "🇨🇼", "🇨🇽", "🇨🇾", "🇨🇿", "🇩🇪", "🇩🇬",
                    "🇩🇯", "🇩🇰", "🇩🇲", "🇩🇴", "🇩🇿", "🇪🇦", "🇪🇨", "🇪🇪", "🇪🇬", "🇪🇭", "🇪🇷", "🇪🇸",
                    "🇪🇹", "🇪🇺", "🇫🇮", "🇫🇯", "🇫🇰", "🇫🇲", "🇫🇴", "🇫🇷", "🇬🇦", "🇬🇧", "🇬🇩", "🇬🇪",
                    "🇬🇫", "🇬🇬", "🇬🇭", "🇬🇮", "🇬🇱", "🇬🇲", "🇬🇳", "🇬🇵", "🇬🇶", "🇬🇷", "🇬🇸", "🇬🇹",
                    "🇬🇺", "🇬🇼", "🇬🇾", "🇭🇰", "🇭🇲", "🇭🇳", "🇭🇷", "🇭🇹", "🇭🇺", "🇮🇨", "🇮🇩", "🇮🇪",
                    "🇮🇱", "🇮🇲", "🇮🇳", "🇮🇴", "🇮🇶", "🇮🇷", "🇮🇸", "🇮🇹", "🇯🇪", "🇯🇲", "🇯🇴", "🇯🇵",
                    "🇰🇪", "🇰🇬", "🇰🇭", "🇰🇮", "🇰🇲", "🇰🇳", "🇰🇵", "🇰🇷", "🇰🇼", "🇰🇾", "🇰🇿", "🇱🇦",
                    "🇱🇧", "🇱🇨", "🇱🇮", "🇱🇰", "🇱🇷", "🇱🇸", "🇱🇹", "🇱🇺", "🇱🇻", "🇱🇾", "🇲🇦", "🇲🇨",
                    "🇲🇩", "🇲🇪", "🇲🇫", "🇲🇬", "🇲🇭", "🇲🇰", "🇲🇱", "🇲🇲", "🇲🇳", "🇲🇴", "🇲🇵", "🇲🇶",
                    "🇲🇷", "🇲🇸", "🇲🇹", "🇲🇺", "🇲🇻", "🇲🇼", "🇲🇽", "🇲🇾", "🇲🇿", "🇳🇦", "🇳🇨", "🇳🇪",
                    "🇳🇫", "🇳🇬", "🇳🇮", "🇳🇱", "🇳🇴", "🇳🇵", "🇳🇷", "🇳🇺", "🇳🇿", "🇴🇲", "🇵🇦", "🇵🇪",
                    "🇵🇫", "🇵🇬", "🇵🇭", "🇵🇰", "🇵🇱", "🇵🇲", "🇵🇳", "🇵🇷", "🇵🇸", "🇵🇹", "🇵🇼", "🇵🇾",
                    "🇶🇦", "🇷🇪", "🇷🇴", "🇷🇸", "🇷🇺", "🇷🇼", "🇸🇦", "🇸🇧", "🇸🇨", "🇸🇩", "🇸🇪", "🇸🇬",
                    "🇸🇭", "🇸🇮", "🇸🇯", "🇸🇰", "🇸🇱", "🇸🇲", "🇸🇳", "🇸🇴", "🇸🇷", "🇸🇸", "🇸🇹", "🇸🇻",
                    "🇸🇽", "🇸🇾", "🇸🇿", "🇹🇦", "🇹🇨", "🇹🇩", "🇹🇫", "🇹🇬", "🇹🇭", "🇹🇯", "🇹🇰", "🇹🇱",
                    "🇹🇲", "🇹🇳", "🇹🇴", "🇹🇷", "🇹🇹", "🇹🇻", "🇹🇼", "🇹🇿", "🇺🇦", "🇺🇬", "🇺🇲", "🇺🇳",
                    "🇺🇸", "🇺🇾", "🇺🇿", "🇻🇦", "🇻🇨", "🇻🇪", "🇻🇬", "🇻🇮", "🇻🇳", "🇻🇺", "🇼🇫", "🇼🇸",
                    "🇽🇰", "🇾🇪", "🇾🇹", "🇿🇦", "🇿🇲", "🇿🇼"
                ]
            ]
            
            // Character limit for comment
            let characterLimit = 50
            
            // Initialize the view and reset emoji state
            init(comment: Binding<String>, selectedEmoji: Binding<String>, isPresented: Binding<Bool>, onSubmit: @escaping (String, String) -> Void) {
                self._comment = comment
                self._selectedEmoji = selectedEmoji
                self._isPresented = isPresented
                self.onSubmit = onSubmit
                
                // Initialize displayed emojis with original options
                self._displayedEmojis = State(initialValue: ["🥴", "😂", "💔", "💀", "🔥"])
            }
            
            // Add the emojis with plus to the view
            var mainEmojisWithPlus: [AnyView] {
                var views = displayedEmojis.prefix(maxVisibleEmojis).enumerated().map { index, emoji in
                    AnyView(
                        Button(action: {
                            selectedEmoji = emoji
                        }) {
                            Text(emoji)
                                .font(.system(size: 30))
                                .padding(8)
                                .background(
                                    Circle()
                                        .fill(selectedEmoji == emoji ? Color.customPink.opacity(0.2) : Color.clear)
                                )
                        }
                    )
                }
                
                // Add the "plus" button as shown in screenshot
                views.append(AnyView(
                    Button(action: {
                        dismissKeyboard() // Add this line to dismiss keyboard
                        showingEmojiPicker = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(Color.customPink))
                    }
                ))
                
                return views
            }
            
            // Function to limit newlines to a maximum of 3
            private func limitNewlines(in text: String) -> String {
                // Count newlines in the text
                let newlineCount = text.filter { $0 == "\n" }.count
                
                // If there are more than 3 newlines, reduce them
                if newlineCount > 3 {
                    // Split text by newlines
                    var lines = text.components(separatedBy: "\n")
                    
                    // If we have more than 4 lines (which means 3 newlines)
                    // Keep only first 4 lines to have 3 newlines
                    if lines.count > 4 {
                        lines = Array(lines.prefix(4))
                    }
                    
                    // Rejoin with newlines
                    return lines.joined(separator: "\n")
                }
                
                // Return original text if it has 3 or fewer newlines
                return text
            }
            
            var body: some View {
                NavigationView {
                    VStack(spacing: 20) {
                        // Fixed emoji selector (no scrolling)
                        VStack(alignment: .leading) {
                            Text("Select emoji")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            // Fixed HStack with emojis and plus button
                            HStack(spacing: 15) {
                                ForEach(0..<mainEmojisWithPlus.count, id: \.self) { index in
                                    mainEmojisWithPlus[index]
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 10)
                        .onAppear {
                            // Reset emojis to original on view appear
                            displayedEmojis = originalEmojiOptions
                            selectedEmoji = originalEmojiOptions[0]
                        }
                        
                        // Comment field
                        VStack(alignment: .leading) {
                            Text("Add your comment")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ZStack(alignment: .bottomTrailing) {
                                TextEditor(text: $comment)
                                    .padding(5)
                                    .frame(height: 150)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .onChange(of: comment) { newValue in
                                        // First, enforce character limit
                                        if newValue.count > characterLimit {
                                            comment = String(newValue.prefix(characterLimit))
                                        }
                                        
                                        // Then, limit the number of newlines
                                        comment = limitNewlines(in: comment)
                                    }
                                
                                Text("\(comment.count)/\(characterLimit)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(8)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Location warning message
                        Text("Your temporary location will be recorded as a snapshot by submitting this pin")
                            .font(.caption)
                            .foregroundColor(Color.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.top, 5)
                        
                        // Submit button
                        Button(action: {
                            onSubmit(comment, selectedEmoji)
                            isPresented = false
                            // State will reset on next appearance
                        }) {
                            Text("Submit")
                                .fontWeight(.medium)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .background(comment.isEmpty ? Color.gray : Color.customPink)
                                .cornerRadius(10)
                                .padding(.horizontal)
                        }
                        .disabled(comment.isEmpty)
                        
                        Spacer()
                    }
                    .padding(.top, 20)
                    .navigationTitle("New Pin")
                    .navigationBarItems(trailing: Button("Cancel") {
                        isPresented = false
                        // State will reset on next appearance
                    }
                        .foregroundColor(.customPink))
                    // Full emoji picker overlay
                    .overlay(
                        Group {
                            if showingEmojiPicker {
                                // Semi-transparent background
                                Color.black.opacity(0.3)
                                    .ignoresSafeArea()
                                    .onTapGesture {
                                        showingEmojiPicker = false
                                    }
                                
                                // Emoji picker popup
                                VStack(spacing: 0) {
                                    // Header with category name - matching screenshot "SYMBOLS & PEOPLE"
                                    Text(selectedCategory.uppercased())
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal)
                                        .padding(.top, 10)
                                        .padding(.bottom, 5)
                                    
                                    // Emoji grid
                                    ScrollView {
                                        LazyVGrid(columns: [
                                            GridItem(.flexible()),
                                            GridItem(.flexible()),
                                            GridItem(.flexible()),
                                            GridItem(.flexible()),
                                            GridItem(.flexible()),
                                            GridItem(.flexible()),
                                            GridItem(.flexible())
                                        ], spacing: 12) {
                                            ForEach(emojisByCategory[selectedCategory] ?? [], id: \.self) { emoji in
                                                Button(action: {
                                                    handleEmojiSelection(emoji)
                                                    showingEmojiPicker = false
                                                }) {
                                                    Text(emoji)
                                                        .font(.system(size: 24))
                                                }
                                            }
                                        }
                                        .padding()
                                    }
                                    
                                    // Fixed non-scrollable category selector at bottom (matching screenshot)
                                    HStack(spacing: 8) {
                                        ForEach(categories, id: \.self) { category in
                                            Button(action: {
                                                selectedCategory = category
                                            }) {
                                                Image(systemName: categoryIcon(for: category))
                                                    .font(.system(size: 20))
                                                    .foregroundColor(selectedCategory == category ? .customPink : .gray)
                                                    .frame(width: 40)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.systemGray6))
                                }
                                // Make popup bigger to accommodate all category icons without scrolling
                                .frame(width: UIScreen.main.bounds.width * 0.9, height: UIScreen.main.bounds.height * 0.6)
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .shadow(radius: 10)
                            }
                        }
                    )
                }
            }
            
            // New function to handle emoji selection from the popup
            private func handleEmojiSelection(_ emoji: String) {
                // Set selected emoji
                selectedEmoji = emoji
                
                // If the emoji is already in the displayed list, remove it first to avoid duplicates
                displayedEmojis.removeAll(where: { $0 == emoji })
                
                // Insert the newly selected emoji at the beginning
                displayedEmojis.insert(emoji, at: 0)
                
                // If we have more than the maximum allowed emojis, trim the list
                if displayedEmojis.count > maxVisibleEmojis {
                    displayedEmojis = Array(displayedEmojis.prefix(maxVisibleEmojis))
                }
            }
            
            // Helper function to get icons for each category (matching the screenshot)
            func categoryIcon(for category: String) -> String {
                switch category {
                case "Smileys": return "face.smiling"
                case "People": return "person"
                case "Animals": return "pawprint"
                case "Food": return "fork.knife"
                case "Activities": return "sportscourt"
                case "Travel": return "car"
                case "Objects": return "lightbulb"
                case "Symbols": return "heart" // Selected in the screenshot
                default: return "circle"
                }
            }
        }
        
        struct ActivityPopupView: View {
            @Binding var isPresented: Bool
            @State private var likedPosts: [LikedPost] = []
            @State private var trendingPosts: [LikedPost] = [] // New array for trending posts
            @State private var previouslySeenIds: Set<Int> = [] // Track which posts user has already seen
            @State private var postsWithNewLikes: [Int] = [] // Track posts with new likes
            @Environment(\.colorScheme) var colorScheme
            
            // Add a state variable to track the current filter
            @State private var selectedFilter: ActivityFilter = .all
            
            let onPostTap: (LikedPost) -> Void
            
            // Define filter options
            enum ActivityFilter {
                case all
                case trending
                case yourPosts
            }
            
            private func parsePostgresTimestamp(_ timestamp: String) -> Date? {
                if timestamp.isEmpty { return nil }
                
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                
                // Try different formats
                let formats = [
                    "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
                    "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                    "yyyy-MM-dd HH:mm:ss.SSSSSSZZZ"
                ]
                
                for format in formats {
                    dateFormatter.dateFormat = format
                    if let date = dateFormatter.date(from: timestamp) {
                        return date
                    }
                }
                
                return nil
            }
            
            // Model to represent posts with likes
            struct LikedPost: Identifiable {
                let id: Int
                let comment: String
                let likeCount: Int
                let lastLikeTime: Date
                let emoji: String
                var seen: Bool = false
                let isTrending: Bool // New property
                
                let latitude: Double
                let longitude: Double
                let zoomLevel: Double
                
                // Format the time difference as a string with consistent increments
                var timeAgo: String {
                    let now = Date()
                    let timeInterval = now.timeIntervalSince(lastLikeTime)
                    
                    // Less than 5 minutes
                    if timeInterval < 300 {
                        return "just now"
                    }
                    // Less than an hour - show in 5 minute increments
                    else if timeInterval < 3600 {
                        let minutes = Int(timeInterval / 60)
                        let roundedMinutes = (minutes / 5) * 5 // Round to nearest 5 minute increment
                        return "\(roundedMinutes)m ago"
                    }
                    // Less than a day - show in hour increments
                    else if timeInterval < 86400 {
                        let hours = Int(timeInterval / 3600)
                        return "\(hours)h ago"
                    }
                    // Less than a week - show in day increments
                    else if timeInterval < 604800 {
                        let days = Int(timeInterval / 86400)
                        return "\(days)d ago"
                    }
                    // Otherwise show in week increments
                    else {
                        let weeks = Int(timeInterval / 604800)
                        return "\(weeks)w ago"
                    }
                }
                
                // Format the comment preview with a 32-character limit
                var commentPreview: String {
                    if comment.count <= 32 {
                        return comment
                    } else {
                        // Find a good break point before 32 characters
                        let maxLength = 32
                        let endIndex = comment.index(comment.startIndex, offsetBy: min(maxLength, comment.count))
                        let truncatedText = String(comment[..<endIndex])
                        
                        // If we're in the middle of a word, find the last space
                        if endIndex < comment.endIndex && !comment[endIndex].isWhitespace {
                            if let lastSpace = truncatedText.lastIndex(where: { $0.isWhitespace }) {
                                return String(comment[..<lastSpace]) + "..."
                            }
                        }
                        
                        return truncatedText + "..."
                    }
                }
                
                // Format the like count text
                var likeText: String {
                    if likeCount == 1 {
                        return "Someone liked your post"
                    } else {
                        return "\(likeCount) people liked your post"
                    }
                }
                
                // Property for trending text
                var trendingText: String {
                    if likeCount == 1 {
                        return "Someone liked this post"
                    } else {
                        return "\(likeCount) people liked this post"
                    }
                }
            }
            
            var body: some View {
                ZStack {
                    // Semi-transparent background
                    Color.black.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            // Close when tapping outside
                            isPresented = false
                            // Mark all as seen when closing
                            markAllAsSeen()
                        }
                    
                    // Activity popup content
                    VStack(spacing: 16) {
                        // Small space at top
                        Color.clear.frame(height: 8)
                        
                        // Header with title, filter buttons, and close button
                        VStack(spacing: 8) {
                            HStack {
                                Button(action: {
                                    isPresented = false
                                    // Mark all as seen when closing
                                    markAllAsSeen()
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.customPink)
                                        .padding(8)
                                }
                                
                                Spacer()
                                
                                Text("Activity")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                
                                Spacer()
                                
                                // Empty view for balance
                                Color.clear
                                    .frame(width: 30, height: 30)
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            
                            // Filter buttons
                            HStack(spacing: 4) {
                                FilterButton(title: "All", isSelected: selectedFilter == .all) {
                                    selectedFilter = .all
                                }
                                
                                FilterButton(title: "VIBIN", isSelected: selectedFilter == .trending) {
                                    selectedFilter = .trending
                                }
                                
                                FilterButton(title: "Your Posts", isSelected: selectedFilter == .yourPosts) {
                                    selectedFilter = .yourPosts
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
                        }
                        
                        Divider()
                        
                        // Activity content
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if likedPosts.isEmpty && trendingPosts.isEmpty {
                                    // Empty state when no activity (keep this as is)
                                    EmptyStateView()
                                } else {
                                    // Show content based on selected filter
                                    if selectedFilter == .all || selectedFilter == .trending {
                                        // Show trending posts section if filter is All or VIBIN
                                        if !trendingPosts.isEmpty {
                                            Text("VIBIN Posts")
                                                .font(.headline)
                                                .fontWeight(.bold)
                                                .foregroundColor(.customPink)
                                                .padding(.horizontal)
                                                .padding(.top, 8)
                                            
                                            // Display each trending post with customPink background
                                            ForEach(trendingPosts) { post in
                                                ActivityRow(
                                                    post: post,
                                                    isTrendingRow: true,
                                                    onTap: onPostTap
                                                )
                                                Divider()
                                            }
                                            
                                            // Add a divider between trending and liked posts sections
                                            if !likedPosts.isEmpty && selectedFilter == .all {
                                                Divider()
                                                    .padding(.vertical, 4)
                                            }
                                        }
                                    }
                                    
                                    if selectedFilter == .all || selectedFilter == .yourPosts {
                                        // Show liked posts section if filter is All or Your Posts
                                        if !likedPosts.isEmpty {
                                            Text("Your Posts")
                                                .font(.headline)
                                                .fontWeight(.bold)
                                                .foregroundColor(.customPink)
                                                .padding(.horizontal)
                                                .padding(.top, selectedFilter == .yourPosts ? 8 : 16)
                                                .padding(.bottom, 8)
                                            
                                            // Split posts into unseen and seen
                                            let unseenPosts = likedPosts.filter { !$0.seen }
                                            let seenPosts = likedPosts.filter { $0.seen }
                                            
                                            // Add "You're all caught up!" message if all posts are seen
                                            if unseenPosts.isEmpty && !seenPosts.isEmpty {
                                                Text("You're all caught up!")
                                                    .font(.caption)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(colorScheme == .dark ? .white : .darkGray)
                                                    .frame(maxWidth: .infinity, alignment: .center)
                                                    .padding(.vertical, 8)
                                            }
                                            
                                            // Display unseen posts
                                            ForEach(unseenPosts) { post in
                                                ActivityRow(
                                                    post: post,
                                                    isTrendingRow: false,
                                                    seen: false,
                                                    onTap: onPostTap
                                                )
                                                Divider()
                                            }
                                            
                                            // Display seen posts with label
                                            if !seenPosts.isEmpty {
                                                if !unseenPosts.isEmpty {
                                                    Text("Previously Seen")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                        .padding(.horizontal)
                                                        .padding(.top, 8)
                                                }
                                                
                                                ForEach(seenPosts) { post in
                                                    ActivityRow(
                                                        post: post,
                                                        isTrendingRow: false,
                                                        seen: true,
                                                        onTap: onPostTap
                                                    )
                                                    Divider()
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Show empty state message for filter with no content
                                    if (selectedFilter == .trending && trendingPosts.isEmpty) ||
                                       (selectedFilter == .yourPosts && likedPosts.isEmpty) {
                                        EmptyFilterStateView(filter: selectedFilter)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .background(colorScheme == .dark ? Color.black : Color.white)
                    .cornerRadius(16)
                    .shadow(radius: 10)
                    .frame(width: UIScreen.main.bounds.width * 0.85, height: UIScreen.main.bounds.height * 0.6)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isPresented)
                .onAppear {
                    // Load liked posts data when the view appears
                    loadLikedPosts()
                    
                    // Load trending posts
                    loadTrendingPosts()
                    
                    // Load previously seen post IDs from UserDefaults
                    loadSeenPostIds()
                }
            }
            
            // Filter button component
            private struct FilterButton: View {
                let title: String
                let isSelected: Bool
                let action: () -> Void
                @Environment(\.colorScheme) var colorScheme
                
                var body: some View {
                    Button(action: action) {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.gray.opacity(0.2) : Color.clear)
                            .foregroundColor(isSelected ? .gray :
                                            (colorScheme == .dark ? .white : .black))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color.gray.opacity(0.4) :
                                           (colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6)),
                                           lineWidth: 1)
                            )
                    }
                }
            }
            
            // Empty state view when no activity
            private struct EmptyStateView: View {
                var body: some View {
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: "heart.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text("No activity yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        Text("When someone interacts with your posts, you'll see it here")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Spacer()
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                }
            }
            
            // Empty filter state view
            private struct EmptyFilterStateView: View {
                let filter: ActivityFilter
                
                var body: some View {
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: filter == .trending ? "flame.slash" : "heart.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text(filter == .trending ? "No VIBIN posts yet" : "No liked posts yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        Text(filter == .trending ?
                             "Posts with multiple likes will appear here" :
                             "When someone likes your posts, they'll appear here")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Spacer()
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                }
            }
            
            // Helper function to mark all posts as seen and save to UserDefaults
            private func markAllAsSeen() {
                // Extract all post IDs
                let allIds = Set(likedPosts.map { $0.id })
                
                // Get current seen IDs
                var currentSeenIds = UserDefaults.standard.array(forKey: "seenActivityPostIds") as? [Int] ?? []
                
                // Add all new IDs from this session
                let updatedSeenIds = currentSeenIds + Array(allIds.filter { !currentSeenIds.contains($0) })
                
                // Save back to UserDefaults
                UserDefaults.standard.set(updatedSeenIds, forKey: "seenActivityPostIds")
                
                // Clear the posts with new likes
                UserDefaults.standard.set([], forKey: "postsWithNewLikes")
                
                // Update the previous total likes count
                Task {
                    do {
                        if let currentUser = try? await supabase.auth.session.user {
                            // Count total likes from others
                            var totalLikesFromOthers = 0
                            var updatedPostLikes: [String: Int] = [:]
                            
                            for post in likedPosts {
                                totalLikesFromOthers += post.likeCount
                                updatedPostLikes[String(post.id)] = post.likeCount
                            }
                            
                            // Save the current counts
                            UserDefaults.standard.set(totalLikesFromOthers, forKey: "previousTotalLikes")
                            UserDefaults.standard.set(updatedPostLikes, forKey: "previousPostLikes")
                        }
                    } catch {
                        print("Error updating like counts: \(error)")
                    }
                }
            }
            
            // Helper function to load previously seen post IDs
            private func loadSeenPostIds() {
                let seenIds = UserDefaults.standard.array(forKey: "seenActivityPostIds") as? [Int] ?? []
                self.previouslySeenIds = Set(seenIds)
                
                // Load posts with new likes
                self.postsWithNewLikes = UserDefaults.standard.array(forKey: "postsWithNewLikes") as? [Int] ?? []
            }
            
            // New function to load trending posts
            private func loadTrendingPosts() {
                Task {
                    do {
                        let response: [PostWithActivity] = try await supabase
                            .from("Posts")
                            .select("id, emoji, comment, likes, created_at, latitude, longitude, zoom_level")
                            .execute()
                            .value
                        
                        // Calculate which posts are trending (top 15%)
                        if response.count > 5 {
                            // Sort posts by like count in descending order
                            let sortedByLikes = response.sorted {
                                (($0.likes?.count ?? 0) > ($1.likes?.count ?? 0))
                            }
                            
                            // Calculate the threshold for top 15%
                            let thresholdIndex = max(0, Int(Double(sortedByLikes.count) * 0.15) - 1)
                            let likeThreshold = thresholdIndex < sortedByLikes.count ?
                                (sortedByLikes[thresholdIndex].likes?.count ?? 0) : 0
                            
                            // Only consider posts with at least 1 like as trending
                            let minimumLikesForTrending = max(1, likeThreshold)
                            
                            // Filter for trending posts
                            let trendingPostsData = sortedByLikes.filter {
                                ($0.likes?.count ?? 0) >= minimumLikesForTrending && ($0.likes?.count ?? 0) > 0
                            }
                            
                            // Convert to LikedPost model for display
                            var trendingPostsArray: [LikedPost] = []
                            
                            for post in trendingPostsData {
                                let likeTime = parsePostgresTimestamp(post.created_at ?? "") ?? Date()
                                
                                let trendingPost = LikedPost(
                                    id: post.id,
                                    comment: post.comment ?? "",
                                    likeCount: post.likes?.count ?? 0,
                                    lastLikeTime: likeTime,
                                    emoji: post.emoji ?? "🙂",
                                    seen: false, // Not applicable for trending posts
                                    isTrending: true,
                                    latitude: post.latitude ?? 0.0,
                                    longitude: post.longitude ?? 0.0,
                                    zoomLevel: post.zoom_level ?? 18.0
                                )
                                
                                trendingPostsArray.append(trendingPost)
                            }
                            
                            // Sort trending posts by likes (most liked first)
                            trendingPostsArray.sort { $0.likeCount > $1.likeCount }
                            
                            // Update the UI on main thread
                            DispatchQueue.main.async {
                                self.trendingPosts = trendingPostsArray
                            }
                        }
                    } catch {
                        print("Error loading trending posts: \(error)")
                    }
                }
            }
            
            // Function to load liked posts from database
            private func loadLikedPosts() {
                Task {
                    do {
                        if let currentUser = try? await supabase.auth.session.user {
                            let userId = currentUser.id
                            let userIdString = userId.uuidString
                            
                            print("DEBUG: Current user ID: '\(userIdString)'") // Print for debugging
                            
                            // Load previously seen post IDs
                            loadSeenPostIds()
                            
                            // Get all posts by this user
                            let response: [PostWithActivity] = try await supabase
                                .from("Posts")
                                .select("id, emoji, comment, likes, created_at, latitude, longitude, zoom_level")
                                .eq("user_id", value: userIdString)
                                .execute()
                                .value
                            
                            // Process posts to find ones with likes from others
                            var postsWithLikes: [LikedPost] = []
                            
                            for post in response {
                                if let likes = post.likes, !likes.isEmpty {
                                    print("DEBUG: Post \(post.id) likes: \(likes)")
                                    
                                    // Filter out self-likes
                                    let filteredLikes = likes.filter { likeId -> Bool in
                                        let result = likeId != userIdString
                                        if !result {
                                            print("DEBUG: Filtered out self-like: '\(likeId)'")
                                        }
                                        return result
                                    }
                                    
                                    // Only include posts that have likes from others
                                    if !filteredLikes.isEmpty {
                                        let likeTime = parsePostgresTimestamp(post.created_at ?? "") ?? Date()
                                        
                                        // Check if this post has new likes
                                        let hasNewLikes = postsWithNewLikes.contains(post.id)
                                        
                                        // A post is considered "seen" only if it was previously seen AND doesn't have new likes
                                        let seen = previouslySeenIds.contains(post.id) && !hasNewLikes
                                        
                                        let likedPost = LikedPost(
                                            id: post.id,
                                            comment: post.comment ?? "",
                                            likeCount: filteredLikes.count,
                                            lastLikeTime: likeTime,
                                            emoji: post.emoji ?? "🙂",
                                            seen: seen,
                                            isTrending: false, // Regular liked posts are not trending in activity feed
                                            latitude: post.latitude ?? 0.0,
                                            longitude: post.longitude ?? 0.0,
                                            zoomLevel: post.zoom_level ?? 18.0
                                        )
                                        
                                        postsWithLikes.append(likedPost)
                                        print("DEBUG: Added post \(post.id) with \(filteredLikes.count) likes from others")
                                    } else {
                                        print("DEBUG: Post \(post.id) has only self-likes, skipping")
                                    }
                                }
                            }
                            
                            // Sort posts - most recent first, unseen before seen
                            postsWithLikes.sort { $0.lastLikeTime > $1.lastLikeTime }
                            postsWithLikes.sort { !$0.seen && $1.seen }
                            
                            // Update the UI on main thread
                            DispatchQueue.main.async {
                                self.likedPosts = postsWithLikes
                            }
                        }
                    } catch {
                        print("Error loading liked posts: \(error)")
                    }
                }
            }
            
            // Helper view for activity row
            struct ActivityRow: View {
                let post: LikedPost
                let isTrendingRow: Bool
                var seen: Bool = false // Only relevant for non-trending rows
                let onTap: (LikedPost) -> Void
                
                var body: some View {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.customPink.opacity(0.2))
                                .frame(width: 40, height: 40)
                            
                            if isTrendingRow {
                                // Show fire emoji for trending posts
                                Text("🔥")
                                    .font(.system(size: 18))
                            } else {
                                // Show hearts for liked posts as before
                                if post.likeCount > 1 {
                                    // First heart (slightly offset to the left and back)
                                    Text("❤️")
                                        .font(.system(size: 18))
                                        .offset(x: -4, y: 0)
                                    
                                    // Second heart (slightly offset to the right and front)
                                    Text("❤️")
                                        .font(.system(size: 18))
                                        .offset(x: 4, y: 0)
                                } else {
                                    // Single heart for one like
                                    Text("❤️")
                                        .font(.system(size: 18))
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isTrendingRow ? post.trendingText : post.likeText)
                                .font(.system(size: 16, weight: .medium))
                            
                            Text(post.commentPreview)
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                            
                            Text(post.timeAgo)
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Display the emoji from the post that received likes
                        Text(post.emoji)
                            .font(.system(size: 28))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(
                        isTrendingRow ? Color.customPink.opacity(0.1) : // Trending posts have light pink background
                        (seen ? Color(.systemGray6) : Color.clear) // Liked posts have gray or clear background
                    )
                    .cornerRadius(8)
                    .contentShape(Rectangle()) // Make the entire row tappable
                    .onTapGesture {
                        onTap(post)
                    }
                }
            }
        }
    }
    
    // Helper struct for decoding posts from database
    struct PostWithActivity: Decodable {
        let id: Int
        let emoji: String?
        let comment: String?
        let likes: [String]?
        let created_at: String?
        let latitude: Double?
        let longitude: Double?
        let zoom_level: Double?
    }
    
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
}
