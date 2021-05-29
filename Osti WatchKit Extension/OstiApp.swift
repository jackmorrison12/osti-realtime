/*
See LICENSE folder for this sample’s licensing information.

Abstract:
This file defines the Osti app.
*/

import SwiftUI

@main
struct OstiApp: App {
    // This is the business logic.
    var workoutManager = WorkoutManager()

    // Return the scene.
    var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView()
                    .environmentObject(workoutManager)
            }
        }
    }
}
