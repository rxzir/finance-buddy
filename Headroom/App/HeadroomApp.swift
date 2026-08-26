//
//  HeadroomApp.swift
//  Headroom
//
//  Created by Razi on 09/07/2026.
//

import SwiftUI

@main
struct HeadroomApp: App {
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
