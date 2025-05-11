import SwiftUI

struct EULAView: View {
    @Binding var isPresented: Bool
    @Binding var hasAgreed: Bool
    @State private var showErrorMessage = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Text("EULA Agreement: End-User License Agreement")
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.top)
                    .multilineTextAlignment(.center)
                
                ScrollView {
                    Text(eulaText)
                        .font(.system(size: 14))
                        .padding()
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .frame(height: 350)
                .padding(.horizontal)
                
                VStack(spacing: 15) {
                    Button(action: {
                        hasAgreed = true
                        isPresented = false
                    }) {
                        Text("I Agree")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.customPink)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        showErrorMessage = true
                        
                        // Auto-hide error message after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            self.showErrorMessage = false
                        }
                    }) {
                        Text("I Do Not Agree")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    if showErrorMessage {
                        Text("You must agree to enter VibeCheck")
                            .foregroundColor(.red)
                            .font(.callout)
                            .padding(.top, 5)
                            .transition(.opacity)
                            .animation(.easeInOut, value: showErrorMessage)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 10)
            .padding(.horizontal, 30)
        }
    }
    
    // EULA Text
    private let eulaText = """
    END USER LICENSE AGREEMENT FOR VIBECHECK
    
    IMPORTANT: PLEASE READ THIS END USER LICENSE AGREEMENT CAREFULLY BEFORE USING THE VIBECHECK APPLICATION.
    
    1. AGREEMENT
    By downloading, installing, or using the VibeCheck application ("App"), you agree to be bound by the terms of this End User License Agreement ("Agreement"). If you do not agree to these terms, do not use the App.
    
    2. LICENSE GRANT
    Subject to your compliance with this Agreement, you are granted a limited, non-exclusive, non-transferable license to use the App for personal, non-commercial purposes.
    
    3. CONTENT POLICY
    VibeCheck is a location-based social platform that allows users to create and view posts at specific geographic locations. By using the App, you agree to adhere to the following content guidelines:
    
    a) PROHIBITED CONTENT:
       • Hate speech, discrimination, or content that promotes intolerance based on race, gender, religion, nationality, disability, sexual orientation, or age
       • Threats, harassment, bullying, or content intended to intimidate or shame others
       • Sexually explicit or pornographic material
       • Content promoting violence, self-harm, dangerous activities, or illegal behavior
       • Personal information of others without their consent
       • Spam, scams, or misleading information
       • Content that infringes on intellectual property rights
    
    b) ZERO TOLERANCE POLICY:
       VibeCheck maintains a strict zero-tolerance policy for objectionable content and abusive behavior. Users found in violation of these guidelines may have their content removed without notice and may be permanently banned from the platform.
    
    4. USER ACCOUNTS AND CONDUCT
    a) You are responsible for maintaining the confidentiality of your account credentials.
    
    b) You agree to use the App in a manner consistent with all applicable laws and regulations.
    
    c) You will not use the App to impersonate others or misrepresent your identity.
    
    d) You will not attempt to access, tamper with, or use non-public areas of the App.
    
    5. USER-GENERATED CONTENT
    a) You retain ownership of content you create and share through the App.
    
    b) By posting content, you grant VibeCheck a worldwide, non-exclusive, royalty-free license to use, reproduce, modify, adapt, publish, and display such content in connection with providing and promoting the App.
    
    c) VibeCheck reserves the right to remove any content that violates this Agreement or that is otherwise objectionable.
    
    6. PRIVACY
    a) Our collection and use of personal information is governed by our Privacy Policy.
    
    b) Location Data: VibeCheck requires access to your device's location to function properly. This location data is used to display relevant content and allow you to create location-based posts.
    
    7. TERMINATION
    VibeCheck reserves the right to suspend or terminate your access to the App at any time for violations of this Agreement or for any other reason at its sole discretion.
    
    8. DISCLAIMER OF WARRANTIES
    THE APP IS PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED. TO THE FULLEST EXTENT PERMITTED BY LAW, VIBECHECK DISCLAIMS ALL WARRANTIES, INCLUDING IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.
    
    9. LIMITATION OF LIABILITY
    TO THE EXTENT PERMITTED BY LAW, VIBECHECK SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS OR REVENUES.
    
    10. CHANGES TO THIS AGREEMENT
    VibeCheck reserves the right to modify this Agreement at any time. Continued use of the App after such modifications constitutes acceptance of the updated terms.
    
    11. GOVERNING LAW
    This Agreement shall be governed by the laws of the United States.
    
    By using VibeCheck, you acknowledge that you have read this Agreement, understand it, and agree to be bound by its terms and conditions.
    """
}
