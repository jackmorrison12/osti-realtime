/*
See LICENSE folder for this sample’s licensing information.

Abstract:
This file contains the business logic, which is the interface to HealthKit.
*/

import Foundation
import HealthKit
import Combine
import SwiftyJSON

extension Unicode.Scalar {
    var name: String? {
        guard var escapedName =
                "\(self)".applyingTransform(.toUnicodeName,
                                            reverse: false)
        else {
            return nil
        }

        escapedName.removeFirst(3) // remove "\\N{"
        escapedName.removeLast(1) // remove "}"

        return escapedName
    }
}


class WorkoutManager: NSObject, ObservableObject {
    
    /// - Tag: DeclareSessionBuilder
    let healthStore = HKHealthStore()
    var session: HKWorkoutSession!
    var builder: HKLiveWorkoutBuilder!
    
    // Publish the following:
    // - heartrate
    // - active calories
    // - distance moved
    // - elapsed time
    
    /// - Tag: Publishers
    @Published var heartrate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var distance: Double = 0
    @Published var elapsedSeconds: Int = 0
    
    // The app's workout state.
    var running: Bool = false
    
    /// - Tag: TimerSetup
    // The cancellable holds the timer publisher.
    var start: Date = Date()
    var cancellable: Cancellable?
    var accumulatedTime: Int = 0
    
    /// - Tag: Osti Data
    var uid = "606c78c40326f734f14f326b"
    var timer: Timer?
    var result: JSON = []
    var songDeltaMap: JSON = []
    var trackInfoMap: JSON = []
    var recs: [JSON] = []
    var playedSongs: Set<String> = []
    var wrongCount = 0
    var lastPlaying: String = ""

    // Set up and start the timer.
    func setUpTimer() {
        start = Date()
        cancellable = Timer.publish(every: 0.1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.elapsedSeconds = self.incrementElapsedTime()
            }
    }
    
    // Calculate the elapsed time.
    func incrementElapsedTime() -> Int {
        let runningTime: Int = Int(-1 * (self.start.timeIntervalSinceNow))
        return self.accumulatedTime + runningTime
    }
    
    // Request authorization to access HealthKit.
    func requestAuthorization() {
        // Requesting authorization.
        /// - Tag: RequestAuthorization
        // The quantity type to write to the health store.
        let typesToShare: Set = [
            HKQuantityType.workoutType()
        ]
        
        // The quantity types to read from the health store.
        let typesToRead: Set = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]
        
        // Request authorization for those quantity types.
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            // Handle error.
        }
    }
    
    // Provide the workout configuration.
    func workoutConfiguration(activityType: HKWorkoutActivityType) -> HKWorkoutConfiguration {
        /// - Tag: WorkoutConfiguration
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .indoor
        
        return configuration
    }
    
    // Start the workout.
    func startWorkout(wid: String, activityType: HKWorkoutActivityType) {
        
        result = getInitialData(uid, wid)
        print(result["playlist"])
        
//        If a spotify playlist exists, play that, else queue all the tracks then play
        if (result["playlist"]["spotify_playlist"].exists()) {
            playPlaylist(uid, result["playlist"]["spotify_playlist"]["id"].stringValue)
        } else {
            playTracks(uid, result["playlist"]["tracks"].arrayValue.map {$0.stringValue})
        }
        
        // Start the timer.
        setUpTimer()
        self.running = true
        
        // Create the session and obtain the workout builder.
        /// - Tag: CreateWorkout
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: self.workoutConfiguration(activityType: activityType))
            builder = session.associatedWorkoutBuilder()
        } catch {
            // Handle any exceptions.
            return
        }
        
        // Setup session and builder.
        session.delegate = self
        builder.delegate = self
        
        // Set the workout builder's data source.
        /// - Tag: SetDataSource
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                     workoutConfiguration: workoutConfiguration(activityType: activityType))
        
        // Start the workout session and begin data collection.
        /// - Tag: StartSession
        session.startActivity(with: Date())
        builder.beginCollection(withStart: Date()) { (success, error) in
            // The workout has started.
        }
        
        timer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(checkStats), userInfo: nil, repeats: true)
    }
    
    // MARK: - State Control
    func togglePause() {
        // If you have a timer, then the workout is in progress, so pause it.
        if running == true {
            self.pauseWorkout()
        } else {// if session.state == .paused { // Otherwise, resume the workout.
            resumeWorkout()
        }
    }
    
    func pauseWorkout() {
        // Pause the workout.
        session.pause()
        // Stop the timer.
        cancellable?.cancel()
        // Save the elapsed time.
        accumulatedTime = elapsedSeconds
        running = false
    }
    
    func resumeWorkout() {
        // Resume the workout.
        session.resume()
        // Start the timer.
        setUpTimer()
        running = true
    }
    
    func endWorkout() {
        // End the workout session.
        session.end()
        cancellable?.cancel()
        timer?.invalidate()
        timer = nil
    }
    
    func resetWorkout() {
        // Reset the published values.
        DispatchQueue.main.async {
            self.elapsedSeconds = 0
            self.activeCalories = 0
            self.heartrate = 0
            self.distance = 0
        }
    }
    
    func getInitialData(_ uid: String, _ wid: String) -> JSON {
        // Get the playlist from the database
        guard let url =  URL(string:"https://osti-recommender.herokuapp.com/get_initial_data")
        else{
            return JSON({})
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody =  try? JSONSerialization.data(withJSONObject: ["uid" : uid, "wid": wid])
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request){
            (data, response, error) in
            if let error = error {
                print(error)
                return
            }
            guard let data = data else{
                return
            }
            self.result = JSON(data)
            semaphore.signal()
        }.resume()
        semaphore.wait()
        
        // Use the deltas to make a delta map
        songDeltaMap = result["deltas"]
        trackInfoMap = result["track_data"]
        recs = result["recs"].arrayValue
        return result
    }
    
    func playPlaylist(_ uid: String, _ pid: String) {
        // Get the playlist from the database
        guard let url =  URL(string:"https://osti.uk/api/spotifyControl/playPlaylist")
        else{
            return         }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody =  try? JSONSerialization.data(withJSONObject: ["uid" : uid, "pid": pid])
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request){
            (data, response, error) in
            if let error = error {
                print(error)
                return
            }
            guard let data = data else{
                print(data)
                return
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return
    }
    
    func playTracks(_ uid: String, _ tracks: [String]) {
        print("playing tracks")
        print(tracks)
        // Get the playlist from the database
        guard let url =  URL(string:"https://osti.uk/api/spotifyControl/playTracks")
        else{
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody =  try? JSONSerialization.data(withJSONObject: ["uid" : uid, "tids": tracks])
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request){
            (data, response, error) in
            if let error = error {
                print(error)
                return
            }
            guard let data = data else{
                print(data)
                return
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return
    }
    
    func getCurrentlyPlayingTrack(_ uid: String) -> String {
        // Get the playlist from the database
        guard let url =  URL(string:"https://osti.uk/api/spotifyControl/currentlyPlaying")
        else{
            return ""
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody =  try? JSONSerialization.data(withJSONObject: ["uid" : uid])
        let semaphore = DispatchSemaphore(value: 0)
        var res = JSON({})

        URLSession.shared.dataTask(with: request){
            (data, response, error) in
            if let error = error {
                print(error)
                return
            }
            guard let data = data else{
                return
            }
            res = JSON(data)
            semaphore.signal()
        }.resume()
        semaphore.wait()
        
        // Use the deltas to make a delta map
        if (res["track_id"] != JSON.null) {
            return(res["track_id"].stringValue)
        }
        
        return ""
    }
    
    @objc func checkStats() {
        
        // Get currently playing song. Add to set of songs played
        let currentlyPlaying = getCurrentlyPlayingTrack(uid)
        
        if currentlyPlaying != lastPlaying {
            if lastPlaying.count > 0 {
                print("removing from recommendations:")
                print(lastPlaying)
                self.recs.removeAll(where: {$0["track_id"].stringValue == lastPlaying})
            }
            lastPlaying = currentlyPlaying
        }
        
        if currentlyPlaying.count > 0 {
            playedSongs.insert(currentlyPlaying)
        }
        
        // Get the target values
        let targetLength = result["stats"]["stats"]["average_length"].doubleValue
        let targetHeartRate = result["stats"]["stats"]["average_heart_rate"].doubleValue
        let targetCalories = result["stats"]["stats"]["average_calories"].doubleValue
        let targetDistance = result["stats"]["stats"]["average_distance"].doubleValue
        
        // Calculate the current delta
        
        // Heart rate delta - negative how much hr is above where it should be - we want to find a song where hr delta is this
        let hrDelta = targetHeartRate - heartrate
        if (hrDelta > 0) {
            print("DELTA: HR TOO LOW " + String(hrDelta))
        } else {
            print("DELTA: HR TOO HIGH " + String(hrDelta))
        }
        
        // Calorie delta
        let targetCalsToNow = (Double(elapsedSeconds) / (targetLength*60)) * targetCalories
        let calorieDelta = (targetCalories - (activeCalories - targetCalsToNow)) / (targetLength * 6)
        print("DELTA: CAL DELTA " + String(calorieDelta))
        // Distance delta
        let targetDistToNow = (Double(elapsedSeconds) / (targetLength*60)) * targetDistance
        let distDelta = (targetDistance - (distance - targetDistToNow)) / (targetLength * 6)
        print("DELTA: DIST DELTA " + String(distDelta))
        
        // Calculate the best song which should be played to reach that delta
        // Calculate the 3 metrics:
        
        var trackRankings: [Double] = []
        
        print("recs:")
        print(recs.count)
        
        for (index, rec) in recs.enumerated() {
            var score = 0.0
            
            // Cosine Distance (two, one, zero weighted 5:2:1)
            if (songDeltaMap[rec["track_id"].stringValue].exists()) {
                var targets: [Double] = []
                var avgs: [Double] = []
                if (songDeltaMap[rec["track_id"].stringValue]["two"]["heart_rate"].exists()) {
                    targets.append(songDeltaMap[rec["track_id"].stringValue]["two"]["heart_rate"].doubleValue)
                    avgs.append(hrDelta)
                }
                if (songDeltaMap[rec["track_id"].stringValue]["two"]["calories"].exists()) {
                    targets.append((songDeltaMap[rec["track_id"].stringValue]["two"]["calories"].doubleValue / (trackInfoMap[rec["track_id"].stringValue]["features"]["duration"].doubleValue / 1000.0)) * 10.0)
                    avgs.append(calorieDelta)
                }
                if (songDeltaMap[rec["track_id"].stringValue]["two"]["distance"].exists() && targetDistance > 0) {
                    targets.append((songDeltaMap[rec["track_id"].stringValue]["two"]["distance"].doubleValue / (trackInfoMap[rec["track_id"].stringValue]["features"]["duration"].doubleValue / 1000.0)) * 10.0)
                    avgs.append(distDelta)
                }

                if (targets.count > 1) {
                    // Calculate cdist, * by 0.5, add to score
                    score += 0.5 * (1 - cosineSim(A: targets, B:avgs))
                } else {
                    score += 0.5
                }
                
                targets = []
                avgs = []
                if (songDeltaMap[rec["track_id"].stringValue]["one"]["heart_rate"].exists()) {
                    targets.append(songDeltaMap[rec["track_id"].stringValue]["one"]["heart_rate"].doubleValue)
                    avgs.append(hrDelta)
                }
                if (songDeltaMap[rec["track_id"].stringValue]["one"]["calories"].exists()) {
                    targets.append((songDeltaMap[rec["track_id"].stringValue]["one"]["calories"].doubleValue / (trackInfoMap[rec["track_id"].stringValue]["features"]["duration"].doubleValue / 1000.0)) * 10.0)
                    avgs.append(calorieDelta)
                }
                if (songDeltaMap[rec["track_id"].stringValue]["one"]["distance"].exists()) {
                    targets.append((songDeltaMap[rec["track_id"].stringValue]["one"]["distance"].doubleValue / (trackInfoMap[rec["track_id"].stringValue]["features"]["duration"].doubleValue / 1000.0)) * 10.0)
                    avgs.append(distDelta)
                }
                if (targets.count > 1) {
                    // Calculate cdist, * by 0.2, add to score
                    score += 0.2 * (1 - cosineSim(A: targets, B:avgs))
                } else {
                    score += 0.2
                }
                
                targets = []
                avgs = []
                if (songDeltaMap[rec["track_id"].stringValue]["zero"]["heart_rate"].exists()) {
                    targets.append(songDeltaMap[rec["track_id"].stringValue]["zero"]["heart_rate"].doubleValue)
                    avgs.append(hrDelta)
                }
                if (songDeltaMap[rec["track_id"].stringValue]["zero"]["calories"].exists()) {
                    targets.append((songDeltaMap[rec["track_id"].stringValue]["zero"]["calories"].doubleValue / (trackInfoMap[rec["track_id"].stringValue]["features"]["duration"].doubleValue / 1000.0)) * 10.0)
                    avgs.append(calorieDelta)
                }
                if (songDeltaMap[rec["track_id"].stringValue]["zero"]["distance"].exists()) {
                    targets.append((songDeltaMap[rec["track_id"].stringValue]["zero"]["distance"].doubleValue / (trackInfoMap[rec["track_id"].stringValue]["features"]["duration"].doubleValue / 1000.0)) * 10.0)
                    avgs.append(distDelta)
                }
                if (targets.count > 1) {
                    // Calculate cdist, * by 0.1, add to score
                    score += 0.1 * (1 - cosineSim(A: targets, B:avgs))
                } else {
                    score += 0.1
                }
            } else {
                score += 0.8
            }
            
            // BPM/HR Difference
            
            let tempo = trackInfoMap[rec["track_id"].stringValue]["features"]["tempo"].doubleValue
            score += (0.3 * abs((tempo - targetHeartRate) / targetHeartRate))
            
            // Rec list position
            
            score += (Double(index) / 100000.0)
            
            trackRankings.append(score)
        }
                
        let sortedTracks = argsort(a: trackRankings)
        
        var topRecs:[String] = []
        for i in 0...4 {
            topRecs.append(recs[sortedTracks[i]]["track_id"].stringValue)
            print(trackInfoMap[recs[sortedTracks[i]]["track_id"].stringValue]["name"].stringValue)
            print(trackRankings[sortedTracks[i]])
        }
        
        
        if currentlyPlaying.count > 0 {
            print(wrongCount)
            // if in top 10, do nothing, set wrongCount = 0
            if topRecs.contains(currentlyPlaying) {
                wrongCount = 0
            } else {
                // else - wrongCount += 1

                wrongCount += 1
                if wrongCount > 3 {
                    // If wrongCount >= 3, then recalculate the best songs for the remaining playlist time, then store this
                    // and play them all using playTracks
                    print("Song playing isn't optimal... overriding")
                    print("SKIP: " + currentlyPlaying + " " + String(elapsedSeconds))
                    print(songDeltaMap[topRecs[0]])
                    topRecs = []
                    var currentLength = 0.0
                    var i = 0
                    while(currentLength < ((targetLength*60) - Double(elapsedSeconds)) && i < recs.count) {
                        topRecs.append(recs[sortedTracks[i]]["track_id"].stringValue)
                        currentLength += (trackInfoMap[recs[sortedTracks[i]]["track_id"].stringValue]["features"]["duration"].doubleValue / 1000.0)
                        i += 1
                    }
                    print(topRecs)
                    // play these songs
                    playTracks(uid, topRecs)
                    wrongCount = 0
                }
                
            }
   
        } else {
            // play the top n songs to fill up the rest of workout
            print("No songs playing... lets change that")
            topRecs = []
            var currentLength = 0.0
            var i = 0
            while(currentLength < ((targetLength*60) - Double(elapsedSeconds)) && i < recs.count) {
                topRecs.append(recs[sortedTracks[i]]["track_id"].stringValue)
                currentLength += (trackInfoMap[recs[sortedTracks[i]]["track_id"].stringValue]["features"]["duration"].doubleValue / 1000.0)
                i += 1
            }
            print(topRecs)
            // play these songs
            playTracks(uid, topRecs)
            wrongCount = 0
        }
        
        
    }
    
    // Mark: - https://gist.github.com/joninsky/4a8773f13fb5ff4513060ef03c8035d7
    /** Cosine similarity **/
    private func cosineSim(A: [Double], B: [Double]) -> Double {
        return dot(A: A, B: B) / (magnitude(A: A) * magnitude(A: B))
    }

    /** Dot Product **/
    private func dot(A: [Double], B: [Double]) -> Double {
        var x: Double = 0
        for i in 0...A.count-1 {
            x += A[i] * B[i]
        }
        return x
    }

    /** Vector Magnitude **/
    private func magnitude(A: [Double]) -> Double {
        var x: Double = 0
        for elt in A {
            x += elt * elt
        }
        return sqrt(x)
    }
    
    // Mark: - https://stackoverflow.com/questions/29183149/swift-returning-the-indexes-that-will-sort-an-array-similar-to-numpy-argsort
    private func argsort<T:Comparable>( a : [T] ) -> [Int] {
        var r = Array(a.indices)
        r.sort(by: { a[$0] < a[$1] })
        return r
    }

    
    // MARK: - Update the UI
    // Update the published values.
    func updateForStatistics(_ statistics: HKStatistics?) {
        guard let statistics = statistics else { return }
        
        DispatchQueue.main.async {
            switch statistics.quantityType {
            case HKQuantityType.quantityType(forIdentifier: .heartRate):
                /// - Tag: SetLabel
                let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
                let value = statistics.mostRecentQuantity()?.doubleValue(for: heartRateUnit)
                let roundedValue = Double( round( 1 * value! ) / 1 )
                self.heartrate = roundedValue
            case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                let energyUnit = HKUnit.kilocalorie()
                let value = statistics.sumQuantity()?.doubleValue(for: energyUnit)
                self.activeCalories = Double( round( 1 * value! ) / 1 )
                return
            case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
                let meterUnit = HKUnit.meter()
                let value = statistics.sumQuantity()?.doubleValue(for: meterUnit)
                let roundedValue = Double( round( 1 * value! ) / 1 )
                self.distance = roundedValue
                return
            default:
                return
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate
extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        // Wait for the session to transition states before ending the builder.
        /// - Tag: SaveWorkout
        if toState == .ended {
            print("The workout has now ended.")
            builder.endCollection(withEnd: Date()) { (success, error) in
                self.builder.finishWorkout { (workout, error) in
                    // Optionally display a workout summary to the user.
                    self.resetWorkout()
                }
            }
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        
    }
    
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else {
                return // Nothing to do.
            }
            
            /// - Tag: GetStatistics
            let statistics = workoutBuilder.statistics(for: quantityType)
            
            // Update the published values.
            updateForStatistics(statistics)
        }
    }
}
