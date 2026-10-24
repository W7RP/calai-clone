import PhotosUI
import SwiftUI

/// Throwaway screen for the Phase 0 spike. Each section answers one question from docs/architecture.md.
struct Phase0View: View {
    @State private var model = Phase0Model()
    @State private var pasted = ""
    @State private var prompt = "Say exactly: Hello, world!"
    @State private var imagePrompt = "List the foods in this photo with a rough kcal estimate for each."
    @State private var photoItem: PhotosPickerItem?

    private let info = Bundle.main.infoDictionary ?? [:]

    var body: some View {
        Form {
            Section {
                Text(model.status)
                if let expiresAt = model.expiresAt {
                    LabeledContent("Token expires", value: expiresAt.formatted(date: .omitted, time: .shortened))
                }
                if !model.grantedScopes.isEmpty {
                    Text(model.grantedScopes.joined(separator: " "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Build \(info["CFBundleVersion"] as? String ?? "?") · \(info["BuildCommit"] as? String ?? "?")")
            }

            Section("1. Sign in") {
                Button("Sign in (in-app browser)") {
                    Task { await model.signInWithLoopback() }
                }
                Button("Sign in (Safari + paste back)") {
                    Task { await model.startPasteBack() }
                }
                if model.awaitingPaste {
                    TextField("Paste the 127.0.0.1 address here", text: $pasted, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Finish sign-in") {
                        Task { await model.finishPasteBack(pasted) }
                    }
                    .disabled(pasted.isEmpty)
                }
                if model.isSignedIn {
                    Button("Sign out", role: .destructive) {
                        Task { await model.signOut() }
                    }
                }
            }

            Section("2. Model") {
                Button("Load models") {
                    Task { await model.loadModels() }
                }
                if !model.models.isEmpty {
                    Picker("Model", selection: $model.selectedModel) {
                        ForEach(model.models) { item in
                            Text(item.display_name ?? item.slug).tag(item.slug)
                        }
                    }
                }
            }

            Section("3. Text call") {
                TextField("Prompt", text: $prompt, axis: .vertical)
                Button("Run text call") {
                    Task { await model.runText(prompt: prompt) }
                }
            }

            Section("4. Image call") {
                TextField("Prompt", text: $imagePrompt, axis: .vertical)
                PhotosPicker("Pick a meal or label photo", selection: $photoItem, matching: .images)
            }

            if !model.output.isEmpty {
                Section("Output") {
                    Text(model.output)
                        .textSelection(.enabled)
                }
            }

            if !model.eventLog.isEmpty {
                Section("Log") {
                    ForEach(Array(model.eventLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                    }
                }
            }
        }
        .navigationTitle("Phase 0")
        .disabled(model.isBusy)
        .overlay {
            if model.isBusy { ProgressView() }
        }
        .task { await model.refreshStatus() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.runImage(data, prompt: imagePrompt)
                }
                photoItem = nil
            }
        }
    }
}

#Preview {
    NavigationStack { Phase0View() }
}
