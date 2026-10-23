import UIKit

enum UIApplicationOpener {
    @MainActor
    static func open(_ url: URL) async {
        await UIApplication.shared.open(url)
    }
}
