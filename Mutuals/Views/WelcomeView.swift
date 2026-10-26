import SwiftUI

struct WelcomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Find the accounts you follow that don't follow you back, starting with the people who used to.")
                        .font(.title3)
                    Text("Mutuals reads the data export Instagram gives you. There's no login, and nothing leaves this iPhone.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            Section {
                Button {
                    store.isImporterPresented = true
                } label: {
                    // The dark-mode accent is light, so the label turns dark there.
                    Text("Import Instagram Export")
                        .foregroundStyle(Color("OnAccent"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Pick the zip, or the folder if you unzipped it. Older exports work too; Mutuals orders them by date and compares each with the one before.")
            }

            Section {
                ExportSteps()
                Link(destination: Instagram.exportPage) {
                    Label("Open Export Your Information", systemImage: "arrow.up.forward.square")
                }
            } header: {
                Text("No export yet")
            }

            Section {
                Button("Try with Sample Data") { store.loadSample() }
            }
        }
        .navigationTitle("Mutuals")
    }
}

/// How to request the export inside Instagram.
struct ExportSteps: View {
    private let steps: [String] = [
        "In Instagram, go to Accounts Center > Your information and permissions > Export your information.",
        "Tap Create export, pick your Instagram account, then Export to device.",
        "Under Customize information, select Followers and following.",
        "For the Quiet list, also select your likes, comments, saved posts, story interactions and ads information. None of them include photos.",
        "Set the date range to All time and the format to JSON, then start the export.",
        "When Instagram says it's ready, download the zip and import it here.",
    ]

    var body: some View {
        ForEach(steps.indices, id: \.self) { index in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(index + 1)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(steps[index])
            }
        }
    }
}
