import Foundation

/// Decisions shared by the login plug-in and menu app. No directory or UI work.
enum AuthenticationPolicy {
    enum PasswordCheck: Equatable {
        case ldap, oidc, none
    }

    static func passwordCheck(useLDAP: Bool, useROPG: Bool, hasRefreshToken: Bool) -> PasswordCheck {
        if useLDAP { return .ldap }
        return useROPG || hasRefreshToken ? .oidc : .none
    }

    static func hasAccessToken(_ token: String?) -> Bool {
        guard let token else { return false }
        return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldParseADUsername(localOnly: Bool, domain: String?) -> Bool {
        !localOnly && !(domain?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Error descriptions and userInfo can contain complete token responses or URLs.
    static func errorSummary(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) (\(error.code))"
    }
}

/// A connectivity notification or timeout may finish a wait only once.
/// Own the block observer token so late network events cannot repeat login.
final class LoginConnectivityWait {
    private let center: NotificationCenter
    private var observer: NSObjectProtocol?
    private var timeout: Timer?
    private var completion: ((Bool) -> Void)?
    private var generation: UUID?

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    func start(notification: Notification.Name, timeout interval: TimeInterval, completion: @escaping (Bool) -> Void) {
        cancel()
        let generation = UUID()
        self.generation = generation
        self.completion = completion
        observer = center.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
            self?.finish(connected: true, generation: generation)
        }
        timeout = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.finish(connected: false, generation: generation)
        }
    }

    private func finish(connected: Bool, generation: UUID) {
        guard self.generation == generation else { return }
        let action = completion
        cancel()
        action?(connected)
    }

    func cancel() {
        generation = nil
        timeout?.invalidate()
        timeout = nil
        if let observer { center.removeObserver(observer) }
        observer = nil
        completion = nil
    }

    deinit { cancel() }
}
