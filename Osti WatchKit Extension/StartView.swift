/*
See LICENSE folder for this sample’s licensing information.

Abstract:
This file defines the start view, where the user can start a workout.
*/

import SwiftUI
import Combine
import HealthKit

struct StartView: View {
    
    @EnvironmentObject var workoutSession: WorkoutManager
    
    let startAction: ((String, HKWorkoutActivityType) -> Void)? // The start action callback.
    
    struct Workout: Identifiable {
        let name: String
        let id = UUID()
        let wid: String
        let activityType: HKWorkoutActivityType
    }
    var workouts = [
        Workout(name: "Running", wid:"6091a67f96e683e8598e6792", activityType: .running),
        Workout(name: "Walking", wid:"6091a14a27f7f3b3a9e65134", activityType: .walking),
        Workout(name: "Strength training", wid:"6091a68196e683e8598e6a24", activityType: .traditionalStrengthTraining)
    ]
    
    var body: some View {
//        List(workouts) {
//            Text($0.name).onTapGesture {print("hi")}
//        }
        List(workouts) { workout in
            HStack {
                Text(workout.name).bold()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                self.startAction!(workout.wid, workout.activityType)
//                print(\(workout.wid))
            }
        }.onAppear() {
            // Request HealthKit store authorization.
            self.workoutSession.requestAuthorization()
        }
//        RunButton(action: {
//            self.startAction!() // FixMe!
//        })
//        .onAppear() {
//            // Request HealthKit store authorization.
//            self.workoutSession.requestAuthorization()
//        }
    }
}

//struct InitialView_Previews: PreviewProvider {
//    static var startAction = { }
//    
//    static var previews: some View {
//        StartView(startAction: startAction)
//        .environmentObject(WorkoutManager())
//    }
//}
