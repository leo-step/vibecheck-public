//
//  UserOnboardingManager.swift
//  vibecheck
//
//  Created by Xabier Sardina on 4/17/25.
//


import SwiftUI
import Combine

class UserOnboardingManager: ObservableObject {
    private let hasAgreedToEULAKey = "hasAgreedToEULA"
    
    @Published var shouldShowEULA: Bool = false
    @Published var hasAgreedToEULA: Bool = false
    
    init() {
        // Check if user has previously agreed to EULA
        self.hasAgreedToEULA = UserDefaults.standard.bool(forKey: hasAgreedToEULAKey)
    }
    
    func checkEULAStatus() {
        if !hasAgreedToEULA {
            // User hasn't agreed to EULA, need to show it
            self.shouldShowEULA = true
        }
    }
    
    func userAgreedToEULA() {
        self.hasAgreedToEULA = true
        UserDefaults.standard.set(true, forKey: hasAgreedToEULAKey)
    }
    
    func resetEULAForTesting() {
        // Helper method to clear EULA agreement for testing
        self.hasAgreedToEULA = false
        UserDefaults.standard.set(false, forKey: hasAgreedToEULAKey)
    }
}