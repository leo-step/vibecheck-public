import SwiftUI

struct AppView: View {
  @State var isAuthenticated = false
  @State var isCheckingAuth = true // Renamed for clarity
  @Environment(\.colorScheme) var colorScheme
  
  var body: some View {
    ZStack {
      // Background color that adapts to color scheme
      (colorScheme == .dark ? Color.black : Color.white)
        .edgesIgnoringSafeArea(.all)
      
      // Main content
      Group {
        if isAuthenticated {
          ContentView()
            .opacity(isCheckingAuth ? 0 : 1) // Fade in after auth check
        } else {
          AuthView()
            .opacity(isCheckingAuth ? 0 : 1) // Fade in after auth check
        }
      }
      
      // Loading overlay - only shown while checking
      if isCheckingAuth {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: .customPink))
          .scaleEffect(1.5)
      }
    }
    .onAppear {
      // Start the auth checking process
      checkAuthentication()
    }
  }
  
  private func checkAuthentication() {
    // Use Task to handle async operation
    Task {
      for await state in supabase.auth.authStateChanges {
        if [.initialSession, .signedIn, .signedOut].contains(state.event) {
          // Update auth state
          await MainActor.run {
            isAuthenticated = state.session != nil
            
            // Slight delay before removing loading state for smoother transition
            withAnimation(.easeInOut(duration: 0.3)) {
              isCheckingAuth = false
            }
          }
          
          // We only need the first auth state, so break after processing it
          break
        }
      }
    }
  }
}
