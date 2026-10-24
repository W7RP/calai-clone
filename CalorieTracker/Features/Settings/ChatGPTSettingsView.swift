import SwiftUI

/// Connect the ChatGPT account used for photo and text logging, and pick the model.
struct ChatGPTSettingsView: View {
    @State private var model = Phase0Model()
    @State private var pasted = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: model.isSignedIn ? "Connected" : "Not connected")
                if !model.isSignedIn {
                    Button("Connect ChatGPT") { Task { await model.signInWithLoopback() } }
                    Button("Connect via Safari (fallback)") { Task { await model.startPasteBack() } }
                    if model.awaitingPaste {
                        TextField("Paste the 127.0.0.1 address here", text: $pasted, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Finish connecting") { Task { await model.finishPasteBack(pasted) } }
                            .disabled(pasted.isEmpty)
                    }
                } else {
                    Button("Disconnect", role: .destructive) { Task { await model.signOut() } }
                }
            } footer: {
                Text("AI calls use your ChatGPT plan's allowance. Photos and descriptions go to OpenAI under your account. You can set a weekly cap for this app in ChatGPT → Settings. To use an API key instead, pick another provider in Settings → AI provider.")
            }

            if model.isSignedIn {
                Section("Model") {
                    if model.models.isEmpty {
                        Button("Load available models") { Task { await model.loadModels() } }
                    } else {
                        Picker("Model", selection: $model.selectedModel) {
                            ForEach(model.models) { Text($0.display_name ?? $0.slug).tag($0.slug) }
                        }
                    }
                    if !model.selectedModel.isEmpty {
                        LabeledContent("Using", value: model.selectedModel)
                    }
                }
            }

            if !model.status.isEmpty, model.status != "Not signed in" {
                Section {
                    Text(model.status).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink("Diagnostics (Phase 0 test screen)") { Phase0View() }
            }
        }
        .navigationTitle("ChatGPT")
        .disabled(model.isBusy)
        .task {
            await model.refreshStatus()
            if model.isSignedIn, model.models.isEmpty { await model.loadModels() }
        }
    }
}
