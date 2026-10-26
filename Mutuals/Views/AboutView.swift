import SwiftUI

struct AboutView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section("How it works") {
                Text("Instagram doesn't tell you who unfollowed you. Each export is a snapshot of your lists, and Mutuals compares every new export with the earlier ones. Anyone who followed you before and doesn't now, while you still follow them, shows up under Unfollowed you.")
                Text("Before there are two exports to compare, Mutuals looks for signs that an account is a person: your close friends list, follow requests, stories you hide, and when you followed them. If most of the accounts you followed around the same time follow you back, you were probably following friends then.")
            }

            Section("Privacy") {
                Text("Mutuals has no login and makes no network requests. Exports are read on this iPhone, and the lists stay in the app's storage until you delete them. Unfollowing happens in Instagram; Mutuals only opens the profile.")
            }

            Section("Get a new export") {
                ExportSteps()
                Link(destination: Instagram.exportPage) {
                    Label("Open Export Your Information", systemImage: "arrow.up.forward.square")
                }
            }

            Section {
                Button("Delete All Data", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Removes every imported export and every mark you made.")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all exports and marks?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete All Data", role: .destructive) {
                store.deleteEverything()
                dismiss()
            }
        }
    }
}
