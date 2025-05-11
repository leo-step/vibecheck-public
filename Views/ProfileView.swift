import SwiftUI

struct ProfileView: View {
    @State var username = ""
    @State var fullName = ""
    @State var website = ""
    @EnvironmentObject var emojiPinVM: EmojiPinViewModel
    @State private var filterObjectionableContent = false
    @State var isLoading = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            try? await supabase.auth.signOut()
                        }
                    }
                    
                    if isLoading {
                        ProgressView()
                    }
                }
                
                // Content filtering section
                Section(header: Text("Content Settings")) {
                    Toggle("Filter Out Objectionable Content", isOn: $filterObjectionableContent)
                        .tint(.customPink)
                        .onChange(of: filterObjectionableContent) { newValue in
                            emojiPinVM.updateContentFilter(enabled: newValue)
                        }
                }
                
                // Legal links section
                Section {
                    Link(destination: URL(string: "https://docs.google.com/document/d/1yeVOEYMIgARqvEjiyWXJClaKrNh9ZN2WQKsF4814uME/edit?usp=sharing")!) {
                        Text("Privacy Policy")
                    }
                    
                    Link(destination: URL(string: "https://docs.google.com/document/d/12oiQxoUTtrRXXHzi8Cc2_-Cy_L_uODYmxuq6N1Nzxc4/edit?usp=sharing")!) {
                        Text("Terms of Service")
                    }
                    
                    // Delete account button
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Text("Delete Account")
                                .foregroundColor(.red)
                            if isDeletingAccount {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeletingAccount)
                }
                
                // Reporting section
                Section {
                    VStack(alignment: .center, spacing: 8) {
                        Text("Reach out to this email with issues pertaining to inappropriate activity:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Link("vibecheckoutreach@gmail.com", destination: URL(string: "mailto:vibecheckoutreach@gmail.com")!)
                            .foregroundColor(.customPink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            // Remove the standard navigation title
            .navigationBarTitleDisplayMode(.inline)
            // Add custom title view
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Profile")
                        .font(.title3)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .task {
            await getInitialProfile()
            filterObjectionableContent = emojiPinVM.filterObjectionableContent
        }
        .overlay {
            if showDeleteConfirmation {
                DeleteAccountConfirmationView(
                    onConfirm: {
                        showDeleteConfirmation = false
                        deleteAccount()
                    },
                    onCancel: {
                        showDeleteConfirmation = false
                    }
                )
            }
        }
        .alert("Error Deleting Account", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage)
        }
    }
    
    func getInitialProfile() async {
        do {
            let currentUser = try await supabase.auth.session.user
            
            let profile: Profile =
            try await supabase
                .from("profiles")
                .select()
                .eq("id", value: currentUser.id)
                .single()
                .execute()
                .value
            
            self.username = profile.username ?? ""
            self.fullName = profile.fullName ?? ""
            self.website = profile.website ?? ""
            
        } catch {
            debugPrint(error)
        }
    }
    
    func updateProfileButtonTapped() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let currentUser = try await supabase.auth.session.user
                
                try await supabase
                    .from("profiles")
                    .update(
                        UpdateProfileParams(
                            username: username,
                            fullName: fullName,
                            website: website
                        )
                    )
                    .eq("id", value: currentUser.id)
                    .execute()
            } catch {
                debugPrint(error)
            }
        }
    }
    
    // Function to handle account deletion
    func deleteAccount() {
        isDeletingAccount = true
        
        Task {
            do {
                let currentUser = try await supabase.auth.session.user
                
                // Delete all user data starting with dependent table
                try await supabase
                    .from("Posts")
                    .delete()
                    .eq("user_id", value: currentUser.id)
                    .execute()
                
                // Sign out - this will trigger the auth state change and navigation
                try await supabase.auth.signOut()
                
                // The navigation to AuthView will happen automatically due to auth state change
                
            } catch {
                print("Error deleting account: \(error)")
                await MainActor.run {
                    isDeletingAccount = false
                    showDeleteConfirmation = false
                    showDeleteError = true
                    deleteErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Nested Views

extension ProfileView {
    // Nested confirmation view
    struct DeleteAccountConfirmationView: View {
        var onConfirm: () -> Void
        var onCancel: () -> Void
        
        var body: some View {
            ZStack {
                // Full screen semi-transparent background
                Color.gray.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        onCancel()
                    }
                
                // White popup card - centered with minimal spacing for smallest height
                VStack(spacing: 12) {
                    // Title
                    Text("Delete Account")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                    
                    // Warning message - removed duplicate question
                    Text("This action cannot be undone. Are you sure you want to continue?")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    
                    // Buttons with border and styling from the screenshot
                    VStack(spacing: 0) {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        
                        Divider()
                        
                        Button(action: onConfirm) {
                            Text("Confirm")
                                .foregroundColor(.red)  // Changed from customPink to red
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                    }
                    .background(Color.white)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(16)
                .frame(width: UIScreen.main.bounds.width * 0.8)
                .background(Color.white)
                .cornerRadius(14)
                .shadow(radius: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)  // Center in the screen
            }
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(EmojiPinViewModel())
}
