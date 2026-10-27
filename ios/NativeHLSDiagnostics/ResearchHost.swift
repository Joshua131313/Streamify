import UIKit

/// A minimal, isolated host gives the manual AVFoundation experiment an actual
/// app container and background-session lifecycle. It is never shipped in Streamify.
@main
final class HLSResearchAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
