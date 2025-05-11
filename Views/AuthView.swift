import SwiftUI
import Supabase

struct AuthView: View {
  @Environment(\.colorScheme) var colorScheme
  
  @State private var email = ""
  @State private var password = ""
  @State private var showPasswordField = false
  @State private var isLoading = false
  @State private var result: Result<Void, Error>?
  @State private var showingNonPrincetonAlert = false
  
  // Focus state for the email TextField
  @FocusState private var isEmailFocused: Bool

  var body: some View {
    VStack(spacing: 20) {
      // Logo: Use "logo-white" for dark mode, "logo" otherwise.
      Image("main-logo")
        .resizable()
        .scaledToFit()
        .frame(height: 300)

      // Email TextField
      TextField("Princeton Email", text: $email)
        .textContentType(.emailAddress)
        .autocapitalization(.none)
        .disableAutocorrection(true)
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
        .focused($isEmailFocused)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(isEmailFocused ? Color.white : Color.clear, lineWidth: 2)
            .shadow(color: isEmailFocused ? Color.white.opacity(0.7) : Color.clear, radius: 4)
        )
        .padding(.horizontal)

      // Conditionally show password field for the testing email.
      if email.lowercased() == "testing999@vibecheck.app" && showPasswordField {
        SecureField("Password", text: $password)
          .textContentType(.password)
          .padding()
          .background(Color.gray.opacity(0.2))
          .cornerRadius(8)
          .padding(.horizontal)
      }

      // Show progress indicator if loading
      if isLoading {
        ProgressView()
      }

      // Centered Sign In Button: Background changes based on color scheme.
      HStack {
        Spacer()
        Button(action: signInButtonTapped) {
          Text("Sign in")
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(red: 253/255, green: 34/255, blue: 204/255))
            .cornerRadius(8)
        }
        Spacer()
      }

      // Result Message
      if let result {
        switch result {
        case .success:
          Text("Check your inbox.")
        case .failure(let error):
          Text(error.localizedDescription)
            .foregroundColor(.red)
        }
      }
      
      Spacer()
    }
    .padding()
    .alert("Princeton Email Required", isPresented: $showingNonPrincetonAlert) {
      Button("OK", role: .cancel) { }
    } message: {
      Text("Only Princeton email addresses (@princeton.edu) are allowed.")
    }
    .onOpenURL { url in
      Task {
        do {
          try await supabase.auth.session(from: url)
        } catch {
          self.result = .failure(error)
        }
      }
    }
  }

  func signInButtonTapped() {
    // If the email is the testing email, use the password-based flow.
    if email.lowercased() == "testing999@vibecheck.app" {
      // If the password field isn't shown yet, reveal it.
      if !showPasswordField {
        showPasswordField = true
        return
      }
      
      // If password is empty, return an error.
      if password.isEmpty {
        result = .failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Please enter your password."]))
        return
      }
      
      // Use Supabase's password based sign in.
      Task {
        isLoading = true
        defer { isLoading = false }
        do {
          try await supabase.auth.signIn(email: email, password: password)
          result = .success(())
        } catch {
          result = .failure(error)
        }
      }
    } else {
      // Validate Princeton email for other cases.
      if !isPrincetonEmail(email) {
        showingNonPrincetonAlert = true
        return
      }
      
      // Use OTP based sign in for Princeton email addresses.
      Task {
        isLoading = true
        defer { isLoading = false }
        do {
          try await supabase.auth.signInWithOTP(
            email: email,
            redirectTo: URL(string: "com.leostepanewk.vibecheck://login-callback")
          )
          result = .success(())
        } catch {
          result = .failure(error)
        }
      }
    }
  }
  
  func isPrincetonEmail(_ email: String) -> Bool {
    return email.lowercased().hasSuffix("@princeton.edu")
  }
}

