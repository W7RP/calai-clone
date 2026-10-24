import Observation
import SwiftUI

/// Pick the AI provider, enter its key, server and model, and test it with a tiny request.
struct AIProviderSettingsView: View {
    @State private var model = AIProviderSettingsModel()

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $model.provider) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.pickerTitle).tag(kind)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Provider")
            } footer: {
                Text(model.provider.summary)
            }

            if model.provider == .chatGPT {
                Section {
                    NavigationLink("ChatGPT account and model") { ChatGPTSettingsView() }
                }
            } else {
                if model.provider == .openAICompatible {
                    serverSection
                }
                keySection
                modelSection
            }

            Section {
                Button("Test with “1 medium apple”") { Task { await model.test() } }
                    .disabled(model.isBusy)
                if let result = model.testResult {
                    Text(result).font(.footnote).foregroundStyle(model.testFailed ? .orange : .secondary)
                }
            } footer: {
                Text("Sends one short text request. Photos and descriptions you log go to the provider you pick, under your own account. Keys stay in this phone's Keychain.")
            }
        }
        .themedList()
        .navigationTitle("AI provider")
        .onChange(of: model.provider) { _, new in model.select(new) }
        .overlay {
            if model.isBusy { ProgressView() }
        }
    }

    private var serverSection: some View {
        Section {
            TextField("https://openrouter.ai/api/v1", text: $model.baseURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { model.saveBaseURL() }
            if !model.baseURL.isEmpty, CustomEndpoint.normalizedBaseURL(model.baseURL) == nil {
                Text("That isn't an http(s) address.").font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Server")
        } footer: {
            Text("The base URL before /chat/completions. Examples: https://openrouter.ai/api/v1, or http://192.168.1.20:11434/v1 for Ollama on your network. Pick a model that accepts images for photo logging.")
        }
    }

    private var keySection: some View {
        Section {
            if let masked = model.savedKeyMasked {
                LabeledContent("Saved key", value: masked)
                Button("Remove key", role: .destructive) { model.removeKey() }
            }
            SecureField(model.savedKeyMasked == nil ? "Paste API key" : "Replace key", text: $model.keyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !model.keyDraft.isEmpty {
                Button("Save key") { model.saveKey() }
            }
            if let url = model.provider.keyPageURL {
                Link("Get a \(model.provider.name) key", destination: url)
            }
        } header: {
            Text(model.provider.requiresAPIKey ? "API key" : "API key (optional)")
        }
    }

    private var modelSection: some View {
        Section {
            TextField("Model ID", text: $model.modelID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { model.saveModel() }
            if model.availableModels.isEmpty {
                Button("Load available models") { Task { await model.loadModels() } }
                    .disabled(model.isBusy)
            } else {
                Picker("Available", selection: $model.modelID) {
                    if !model.availableModels.contains(where: { $0.id == model.modelID }) {
                        Text(model.modelID.isEmpty ? "None" : model.modelID).tag(model.modelID)
                    }
                    ForEach(model.availableModels) { Text($0.label).tag($0.id) }
                }
            }
        } header: {
            Text("Model")
        } footer: {
            if let suggested = model.provider.suggestedModel {
                Text("Suggested: \(suggested). Larger models estimate portions better; smaller ones are cheaper and faster.")
            }
        }
        .onChange(of: model.modelID) { model.saveModel() }
    }
}

@MainActor
@Observable
final class AIProviderSettingsModel {
    var provider = AIProviderSettings.activeProvider
    var modelID = ""
    var baseURL = AIProviderSettings.customBaseURL
    var keyDraft = ""
    private(set) var savedKeyMasked: String?
    private(set) var availableModels: [LLMModel] = []
    private(set) var isBusy = false
    private(set) var testResult: String?
    private(set) var testFailed = false

    init() { load(provider) }

    func select(_ kind: ProviderKind) {
        AIProviderSettings.activeProvider = kind
        load(kind)
    }

    private func load(_ kind: ProviderKind) {
        modelID = AIProviderSettings.model(for: kind)
        savedKeyMasked = APIKeyStore.key(for: kind).map(APIKeyStore.masked)
        keyDraft = ""
        availableModels = []
        testResult = nil
    }

    func saveKey() {
        do {
            try APIKeyStore.save(keyDraft, for: provider)
            savedKeyMasked = APIKeyStore.key(for: provider).map(APIKeyStore.masked)
            keyDraft = ""
            testResult = nil
        } catch {
            show("Couldn't save the key to the Keychain.", failed: true)
        }
    }

    func removeKey() {
        APIKeyStore.delete(for: provider)
        savedKeyMasked = nil
    }

    func saveModel() {
        guard provider != .chatGPT else { return }
        AIProviderSettings.setModel(modelID, for: provider)
    }

    func saveBaseURL() {
        AIProviderSettings.customBaseURL = baseURL
        availableModels = []
    }

    /// Uses a typed-but-unsaved key too, so the user can check it before saving.
    private var config: ProviderConfig {
        var config = AIProviderSettings.config(for: provider)
        config.model = modelID
        if !keyDraft.isEmpty { config.apiKey = keyDraft }
        if provider == .openAICompatible { config.baseURL = CustomEndpoint.normalizedBaseURL(baseURL) }
        return config
    }

    func loadModels() async {
        saveBaseURL()
        isBusy = true
        defer { isBusy = false }
        do {
            availableModels = try await LLMClientFactory.make(config, requireModel: false).listModels()
            if availableModels.isEmpty { show("The provider returned no models.", failed: true) }
        } catch {
            show(error.localizedDescription, failed: true)
        }
    }

    func test() async {
        saveModel()
        if provider == .openAICompatible { saveBaseURL() }
        isBusy = true
        defer { isBusy = false }
        let started = Date.now
        do {
            let estimator = FoodEstimator(client: try LLMClientFactory.make(config))
            let estimate = try await estimator.estimate(description: "1 medium apple", jpeg: nil)
            let seconds = Date.now.timeIntervalSince(started).formatted(.number.precision(.fractionLength(1)))
            let items = estimate.items.map {
                "\($0.name), \(NumberInput.format($0.grams, maxFractionDigits: 0)) g, \(NumberInput.format($0.macros.kcal, maxFractionDigits: 0)) kcal"
            }
            show("Works (\(seconds) s): \(items.joined(separator: "; "))", failed: false)
        } catch {
            show(error.localizedDescription, failed: true)
        }
    }

    private func show(_ text: String, failed: Bool) {
        testResult = text
        testFailed = failed
    }
}
