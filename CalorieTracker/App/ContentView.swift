import SwiftUI

// Placeholder screen for the build-pipeline check. Showing the build number and
// commit makes it obvious on the phone whether a fresh sideload actually took.
struct ContentView: View {
    private let info = Bundle.main.infoDictionary ?? [:]

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Calorie Tracker")
                .font(.title.bold())
            Text("Build \(info["CFBundleVersion"] as? String ?? "?") · \(info["BuildCommit"] as? String ?? "?")")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
