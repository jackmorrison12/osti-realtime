/*
See LICENSE folder for this sample’s licensing information.

Abstract:
This file defines the Osti app.
*/

import SwiftUI
import Foundation

@main
struct OstiApp: App {
    // This is the business logic.
    var workoutManager = WorkoutManager()
    
    init(){
        guard let url =  URL(string:"https://osti-recommender.herokuapp.com/")
        else{
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request){
            (data, response, error) in
            if let error = error {
                print(error)
                return
            }
            guard let data = data else{
                return
            }
            print(data)
        }.resume()

    }

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
