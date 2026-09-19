import SwiftData
import SwiftUI

@main
struct RedFruitTrackerApp: App {
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            SeriesRecord.self,
            SeasonRecord.self,
            EpisodeRecord.self,
            PersonalRecord.self,
            OfficialSnapshot.self,
            ImportInboxItem.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create the local model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
