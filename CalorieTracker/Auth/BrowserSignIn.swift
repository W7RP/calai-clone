import AuthenticationServices
import UIKit

/// Shows the authorize page in an in-app browser. The redirect goes to the loopback listener, not to
/// ASWebAuthenticationSession's own callback matching, so the session is cancelled by hand once the listener fires.
@MainActor
final class BrowserSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var closingOnPurpose = false

    func open(_ url: URL, onDismissedByUser: @escaping @MainActor () -> Void) {
        // The scheme never fires; it only satisfies the API. The real callback is http://127.0.0.1.
        closingOnPurpose = false
        let session = ASWebAuthenticationSession(url: url, callback: .customScheme("calorietracker-unused")) { [weak self] _, error in
            guard let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin else { return }
            Task { @MainActor in
                // close() also reports canceledLogin; only a swipe-down or Cancel tap counts as the user leaving.
                if self?.closingOnPurpose != true { onDismissedByUser() }
            }
        }
        // Reuse the Safari ChatGPT login if there is one.
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = self
        self.session = session
        session.start()
    }

    func close() {
        closingOnPurpose = true
        session?.cancel()
        session = nil
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
