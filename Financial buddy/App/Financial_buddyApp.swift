//
//  Financial_buddyApp.swift
//  Financial buddy
//
//  Created by Razi on 09/07/2026.
//

import SwiftUI

@main
struct Financial_buddyApp: App {
    init() {
        #if canImport(UIKit)
        UITabBar.appearance().tintColor = UIColor(Color.fbAccent)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
