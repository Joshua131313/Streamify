import UIKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@MainActor enum GoogleAccountSignIn {
    static func credential() async throws -> AuthCredential {
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty,
              let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            throw AccountError.unavailable
        }
        var presenter = root
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed { presenter = presented }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let token = result.user.idToken?.tokenString, !token.isEmpty else { throw AccountError.unavailable }
            return GoogleAuthProvider.credential(withIDToken: token, accessToken: result.user.accessToken.tokenString)
        } catch {
            let native = error as NSError
            // Google Sign-In defines user cancellation as -5 in this domain.
            // Its NS_ERROR_ENUM name is imported differently by newer SDKs.
            if native.domain == kGIDSignInErrorDomain, native.code == -5 { throw CancellationError() }
            throw error
        }
    }

    static func handle(_ url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }
    static func signOut() { GIDSignIn.sharedInstance.signOut() }
}
