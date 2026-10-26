import SwiftUI

@main
struct MutualsApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onOpenURL { url in
                    // Zips shared from Files or Mail arrive as copies in Documents/Inbox.
                    store.importFiles([url], removeAfterImport: url.path.contains("/Inbox/"))
                }
        }
    }
}
