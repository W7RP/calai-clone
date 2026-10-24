import Foundation
import Observation

/// Drives the Phase 0 spike screen: sign in two ways, list models, run one text and one image call.
@MainActor
@Observable
final class Phase0Model {
    enum SignInMode { case inAppLoopback, safariPasteBack }

    var status = "Not signed in"
    var isSignedIn = false
    var grantedScopes: [String] = []
    var expiresAt: Date?
    var models: [ResponsesClient.Model] = []
    var selectedModel = UserDefaults.standard.string(forKey: FoodEstimator.modelKey) ?? "" {
        didSet { UserDefaults.standard.set(selectedModel, forKey: FoodEstimator.modelKey) }
    }
    var output = ""
    var eventLog: [String] = []
    var isBusy = false
    var awaitingPaste = false

    private let auth = AuthSession.shared
    private let browser = BrowserSignIn()
    private var listener: LoopbackListener?
    private var pendingAttempt: AuthAttempt?
    private var pendingRedirectURI: String?

    func refreshStatus() async {
        let tokens = await auth.tokens
        isSignedIn = tokens != nil
        grantedScopes = tokens?.grantedScopes ?? []
        expiresAt = tokens?.expiresAt
        if let tokens {
            status = "Signed in · client \(tokens.issuedClientID.prefix(12))…"
        }
    }

    // MARK: Sign-in

    /// Option 1 from docs/openai-signin.md: in-app browser, redirect caught by a listener inside the app.
    func signInWithLoopback() async {
        isBusy = true
        defer { isBusy = false }
        let listener = LoopbackListener()
        self.listener = listener
        do {
            let port = try await listener.start(preferredPort: OpenAIAuthConfig.preferredPort)
            let redirectURI = OpenAIAuthConfig.redirectURI(port: port)
            let attempt = AuthAttempt.make()
            let url = await auth.authorizeURL(attempt: attempt, redirectURI: redirectURI)
            log("Listening on \(redirectURI)")
            browser.open(url) { [weak self] in
                self?.log("Browser closed before the redirect arrived")
                listener.stop()
            }
            let callbackURL = try await listener.waitForCallback()
            browser.close()
            listener.stop()
            log("Redirect caught by the in-app listener")
            try await auth.complete(callback: AuthCallback(url: callbackURL), attempt: attempt, redirectURI: redirectURI)
            log("Token exchange OK")
        } catch {
            browser.close()
            listener.stop()
            fail(error)
        }
        await refreshStatus()
    }

    /// Option 2: open Safari; the redirect fails to load there, and the URL gets pasted back here.
    func startPasteBack() async {
        let attempt = AuthAttempt.make()
        let redirectURI = OpenAIAuthConfig.redirectURI(port: OpenAIAuthConfig.preferredPort)
        pendingAttempt = attempt
        pendingRedirectURI = redirectURI
        awaitingPaste = true
        let url = await auth.authorizeURL(attempt: attempt, redirectURI: redirectURI)
        log("Opened Safari. Copy the address of the page that fails to load and paste it here.")
        await openInSafari(url)
    }

    func finishPasteBack(_ text: String) async {
        guard let attempt = pendingAttempt, let redirectURI = pendingRedirectURI else { return }
        guard let callback = AuthCallback(pasted: text) else {
            status = "That doesn't look like the 127.0.0.1/auth/callback address."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.complete(callback: callback, attempt: attempt, redirectURI: redirectURI)
            awaitingPaste = false
            pendingAttempt = nil
            log("Token exchange OK (paste-back)")
        } catch {
            fail(error)
        }
        await refreshStatus()
    }

    func signOut() async {
        await auth.signOut()
        models = []
        status = "Signed out"
        await refreshStatus()
    }

    // MARK: Inference

    func loadModels() async {
        guard let client = await client() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            models = try await client.listModels()
            if !models.contains(where: { $0.slug == selectedModel }) { selectedModel = models.first?.slug ?? "" }
            log("\(models.count) models available")
        } catch {
            fail(error)
        }
    }

    func runText(prompt: String) async {
        await run(parts: [.text(prompt)])
    }

    func runImage(_ imageData: Data, prompt: String) async {
        guard let jpeg = ImagePreparation.jpegForUpload(imageData) else {
            status = "Couldn't read that image."
            return
        }
        log("Uploading \(jpeg.count / 1024) KB image")
        await run(parts: [.text(prompt), .jpeg(jpeg)])
    }

    private func run(parts: [ResponsesClient.Part]) async {
        guard let client = await client(), !selectedModel.isEmpty else {
            status = "Sign in and load models first."
            return
        }
        isBusy = true
        defer { isBusy = false }
        output = ""
        let started = Date()
        var finished = false
        do {
            let instructions = "You are testing a calorie tracker. Answer briefly. If you estimate nutrition, say it's an estimate."
            for try await event in client.stream(model: selectedModel, instructions: instructions, parts: parts) {
                switch event {
                case .textDelta(let delta):
                    output += delta
                case .completed:
                    finished = true
                    log("completed in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
                case .failed(let code, let message):
                    log("failed: \(code ?? "?") \(message ?? "")")
                case .incomplete(let reason):
                    log("incomplete: \(reason ?? "?")")
                case .error(let code, let message):
                    log("error: \(code ?? "?") \(message ?? "")")
                case .other:
                    break
                }
            }
            status = finished ? "Call succeeded" : "Stream ended without response.completed"
        } catch {
            fail(error)
        }
    }

    private func client() async -> ResponsesClient? {
        guard let tokens = await auth.tokens else {
            status = "Not signed in"
            return nil
        }
        _ = tokens
        do {
            return ResponsesClient(accessToken: try await auth.validAccessToken())
        } catch {
            fail(error)
            return nil
        }
    }

    private func openInSafari(_ url: URL) async {
        await UIApplicationOpener.open(url)
    }

    private func log(_ line: String) {
        eventLog.insert(line, at: 0)
    }

    private func fail(_ error: Error) {
        status = error.localizedDescription
        log("Error: \(error.localizedDescription)")
    }
}
