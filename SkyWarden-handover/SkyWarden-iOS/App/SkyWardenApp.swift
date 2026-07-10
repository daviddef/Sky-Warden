// SkyWarden — App Entry Point

import SwiftUI
import BackgroundTasks
import CoreLocation

@main
struct SkyWardenApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - App Delegate (background refresh)
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerBackgroundTasks()
        scheduleBackgroundRefresh()
        return true
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: SkyWardenID.backgroundRefreshTask,
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()  // Chain the next one

        // Refresh against the last known coordinate written by the foreground app.
        guard let coord = UserDefaults.skyWardenShared?.lastCoordinate else {
            task.setTaskCompleted(success: false)
            return
        }

        let work = Task {
            let aggregator = await WeatherAggregator()
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            await aggregator.backgroundRefresh(location: location)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = { work.cancel() }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: SkyWardenID.backgroundRefreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 900)  // 15 minutes
        try? BGTaskScheduler.shared.submit(request)
    }
}
