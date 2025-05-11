import SwiftUI

struct LikeParams: Encodable {
    let post_id: Int
    let user_id: UUID
}

// Custom button style for better feedback
struct ScaledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct EmojiPinView: View {
    let emoji: String
    let showComment: Bool
    let emojiFontSize: CGFloat
    let comment: String?
    let commentFontSize: CGFloat?
    let isCurrentUserPin: Bool
    let postID: Int
    let isNew: Bool
    let isTrending: Bool
    
    // Change to @State to make it mutable
    @State private var visible: Bool = true
    // Keep these as non-state since we'll update them through the view model
    private var isLiked: Bool
    private var upvotes: Int
    
    // Add reference to view model
    @ObservedObject var viewModel: EmojiPinViewModel
    
    // Add long press manager
    @StateObject private var longPressManager = LongPressManager.shared
    
    var body: some View {
        if !visible {
            EmptyView()
        } else {
            EmojiPinContent
        }
    }
    
    // Extract content into a separate computed property
    private var EmojiPinContent: some View {
        VStack(spacing: 0) {
                // The emoji is always shown
                ZStack {
                    Text(emoji)
                        .font(.system(size: emojiFontSize))
                    
                    // Status badges with conditional display
                    VStack {
                        if isNew {
                            Text("NEW")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                        
                        if isTrending {
                            Text("VIBIN")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.customPink)
                                .clipShape(Capsule())
                        }
                    }
                    .offset(x: 28, y: -16) // Adjust badge position
                }
            
            
            // Show the comment only if showComment == true
            if showComment, let comment = comment, !comment.isEmpty, let fs = commentFontSize {
                ZStack(alignment: .topTrailing) {
                    // Comment box
                    CommentBox(comment: comment, fontSize: fs)
                    
                    // Like button
                    LikeButton
                }
            }
        }
        .fixedSize()
    }
    
    // Extract comment box into a separate computed property
    private func CommentBox(comment: String, fontSize: CGFloat) -> some View {
        Text(comment)
            .foregroundColor(.black)
            .font(.system(size: fontSize))
            .padding(8)
            .frame(maxWidth: 200)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrentUserPin ? Color.customPink : Color.white)
                    .shadow(color: longPressManager.isPinActive(postID) ? Color.customPink.opacity(0.5) : Color.clear,
                            radius: 8, x: 0, y: 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(longPressManager.isPinActive(postID) ? Color.customPink : Color.clear, lineWidth: 2)
            )
            .onLongPressGesture(minimumDuration: 0.5) {
                handleLongPress()
            }
            .onTapGesture(count: 2) {
                handleLikeToggle()
            }
    }
    
    // Extract like button into a separate computed property
    private var LikeButton: some View {
        Button(action: {
            // Call the toggleLike method to handle the like action
            handleLikeToggle()
        }) {
            ZStack {
                ZStack {
                    if isLiked {
                        Image(systemName: "heart.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundColor(.red)
                    } else {
                        Image(systemName: "heart.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundColor(.white)
                        
                        Image(systemName: "heart")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundColor(.gray)
                    }
                }
                
                Text("\(upvotes)")
                    .font(.caption2)
                    .foregroundColor(isLiked ? .white : .gray)
                    .bold()
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(ScaledButtonStyle())
        .offset(x: 16, y: -10)
    }
    
    // Extract long press handling to a separate method
    private func handleLongPress() {
        longPressManager.activatePin(id: postID)
        hapticFeedback()
        
        // Get the key window to present the popup
        let windowScene = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first as? UIWindowScene
        
        if let keyWindow = windowScene?.windows.first(where: { $0.isKeyWindow }) {
            // Create a full-screen overlay view
            let overlayView = UIHostingController(
                rootView: FullScreenPopupView(
                    isCurrentUserPin: isCurrentUserPin,
                    postID: postID,
                    onCompletion: { success in
                        if success {
                            DispatchQueue.main.async {
                                visible = false
                            }
                        }
                        longPressManager.deactivateAllPins()
                    }
                )
            )
            overlayView.view.backgroundColor = .clear
            overlayView.modalPresentationStyle = .overFullScreen
            overlayView.modalTransitionStyle = .crossDissolve // Use crossDissolve for no sliding
            
            // Find the top-most view controller
            var topController = keyWindow.rootViewController
            while let presentedController = topController?.presentedViewController {
                topController = presentedController
            }
            
            // Present the overlay without animation
            topController?.present(overlayView, animated: false)
        }
    }
    
    // Extract like toggle handling to a separate method
    private func handleLikeToggle() {
        // Then use the view model to handle the API call
        Task {
            await viewModel.toggleLike(for: postID)
        }
    }
    
    // Add haptic feedback when long press is detected
    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    // Update initializer to include the view model
    init(emoji: String, showComment: Bool, emojiFontSize: CGFloat, postID: Int, upvotes: Int, isLiked: Bool,
         isNew: Bool, isTrending: Bool, comment: String?, commentFontSize: CGFloat?,
         isCurrentUserPin: Bool = false, viewModel: EmojiPinViewModel) {
        self.emoji = emoji
        self.showComment = showComment
        self.emojiFontSize = emojiFontSize
        self.comment = comment
        self.commentFontSize = commentFontSize
        self.isCurrentUserPin = isCurrentUserPin
        self.isLiked = isLiked
        self.upvotes = upvotes
        self.postID = postID
        self.viewModel = viewModel
        self.isNew = isNew
        self.isTrending = isTrending
    }
}

// Full screen popup view presented at the UIKit level (guaranteed to be centered)
struct FullScreenPopupView: View {
    var isCurrentUserPin: Bool
    var postID: Int
    var onCompletion: (Bool) -> Void
    
    var body: some View {
        PopupContent
    }
    
    // Extract popup content into a separate computed property
    private var PopupContent: some View {
        ZStack {
            // Full screen semi-transparent background
            Color.gray.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    dismissPopup(success: false)
                }
            
            // White popup card with dynamic width based on content type
            VStack(spacing: 15) {
                if isCurrentUserPin {
                    DeleteButton
                } else {
                    FlagBlockButtons
                }
                
                CancelButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            // Dynamic width based on content type
            .frame(width: isCurrentUserPin ? UIScreen.main.bounds.width * 0.65 : UIScreen.main.bounds.width * 0.85)
            .background(Color.white)
            .cornerRadius(14)
            .shadow(radius: 10)
        }
    }
    
    // Extract delete button into a separate computed property
    private var DeleteButton: some View {
        Button(action: {
            handleDeleteAction()
        }) {
            HStack {
                Image(systemName: "trash")
                    .foregroundColor(.white)
                    .font(.system(size: 20))
                Text("Delete")
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                    .font(.system(size: 18))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.red)
            .cornerRadius(10)
        }
        .buttonStyle(ScaledButtonStyle())
    }
    
    // Extract flag and block buttons into a separate computed property
    private var FlagBlockButtons: some View {
        HStack(spacing: 10) {
            // Flag post button
            Button(action: {
                handleFlagAction()
            }) {
                HStack {
                    Image(systemName: "flag")
                        .foregroundColor(.white)
                    Text("Flag Post")
                        .foregroundColor(.white)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.orange)
                .cornerRadius(10)
            }
            .buttonStyle(ScaledButtonStyle())
            
            // Block user button
            Button(action: {
                handleBlockAction()
            }) {
                HStack {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.white)
                    Text("Block User")
                        .foregroundColor(.white)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.gray)
                .cornerRadius(10)
            }
            .buttonStyle(ScaledButtonStyle())
        }
    }
    
    // Extract cancel button into a separate computed property
    private var CancelButton: some View {
        Button(action: {
            dismissPopup(success: false)
        }) {
            Text("Cancel")
                .fontWeight(.medium)
                .foregroundColor(.blue)
                .font(.system(size: 18))
        }
        .padding(.top, 5)
        .buttonStyle(ScaledButtonStyle())
    }
    
    // Extract delete action handling to a separate method
    private func handleDeleteAction() {
        print("DELETE BUTTON PRESSED FOR POST \(postID)")
        Task {
            do {
                let currentUserId = try await supabase.auth.session.user.id
                let response = try await supabase
                    .from("Posts")
                    .delete()
                    .eq("id", value: postID)
                    .eq("user_id", value: currentUserId)
                    .execute()
                
                DispatchQueue.main.async {
                    dismissPopup(success: true)
                }
            } catch {
                print("RPC Error:", error)
                DispatchQueue.main.async {
                    dismissPopup(success: false)
                }
            }
        }
    }
    
    // Extract flag action handling to a separate method
    private func handleFlagAction() {
        print("FLAG BUTTON PRESSED FOR POST \(postID)")
        Task {
            do {
                let currentUserId = try await supabase.auth.session.user.id
                let params = LikeParams(post_id: postID, user_id: currentUserId)
                let function = "block_post"
                try await supabase
                    .rpc(function, params: params)
                    .execute()
                
                DispatchQueue.main.async {
                    dismissPopup(success: true)
                }
            } catch {
                print("RPC Error:", error)
                DispatchQueue.main.async {
                    dismissPopup(success: false)
                }
            }
        }
    }
    
    // Extract block action handling to a separate method
    private func handleBlockAction() {
        print("BLOCK BUTTON PRESSED FOR POST \(postID)")
        Task {
            do {
                let currentUserId = try await supabase.auth.session.user.id
                let params = LikeParams(post_id: postID, user_id: currentUserId)
                let function = "block_post"
                try await supabase
                    .rpc(function, params: params)
                    .execute()
                
                DispatchQueue.main.async {
                    dismissPopup(success: true)
                }
            } catch {
                print("RPC Error:", error)
                DispatchQueue.main.async {
                    dismissPopup(success: false)
                }
            }
        }
    }
    
    private func dismissPopup(success: Bool) {
        if let topController = UIApplication.shared.windows.first?.rootViewController?.presentedViewController {
            // Dismiss without animation
            topController.dismiss(animated: false) {
                onCompletion(success)
            }
        } else {
            onCompletion(success)
        }
    }
}
