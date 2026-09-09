import SwiftUI

@main
struct NOOPiOSApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.live)
                .environmentObject(model.live.offload)
                .environmentObject(model.repo)
                .environmentObject(model.profile)
                .environmentObject(model.behavior)
                .environmentObject(model.intelligence)
                .environmentObject(model.coach)
                .environmentObject(model.healthKit)
                .preferredColorScheme(.dark)
        }
    }
}
