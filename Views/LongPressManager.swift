//
//  LongPressManager.swift
//  vibecheck
//
//  Created by Xabier Sardina on 4/17/25.
//


import SwiftUI

class LongPressManager: ObservableObject {
    static let shared = LongPressManager()
    
    @Published var activePinID: Int? = nil
    
    private init() {}
    
    func activatePin(id: Int) {
        if activePinID == id {
            deactivateAllPins()
        } else {
            activePinID = id
        }
    }
    
    func deactivateAllPins() {
        activePinID = nil
    }
    
    func isPinActive(_ id: Int) -> Bool {
        return activePinID == id
    }
}