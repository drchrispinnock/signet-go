import LocalAuthentication
import SwiftUI
import UIKit

/// The app lock and the privacy cover. Both live in a window of their own above the app's, so
/// they cover open sheets and system pickers too, which a SwiftUI overlay on the root view would
/// not.
///
/// - Cover: whenever the app is not in front (app switcher, Control Centre, a system prompt),
///   so balances and addresses never reach the switcher's snapshot.
/// - Lock: at launch, and on coming back after `grace` seconds in the background, the device
///   owner must authenticate (Face ID, Touch ID or Optic ID, falling back to the passcode).
///   Without a passcode on the device there is nothing to authenticate against, so no lock.
///
/// This guards the app, not the keys: spending keys stay encrypted with their own passwords
/// (`KeyPolicy`), whatever the lock says.
@MainActor @Observable
final class AppLock {
    static let enabledKey = "appLockEnabled"
    static let graceKey = "appLockGrace"
    /// Seconds in the background before the lock comes back, as Settings offers them.
    static let graceChoices: [TimeInterval] = [0, 60, 300]
    static let defaultGrace: TimeInterval = 60

    enum State: Equatable { case unlocked, covered, locked }

    private(set) var state: State = .unlocked
    private(set) var isAuthenticating = false
    private(set) var failure: String?

    private let defaults: UserDefaults
    private var window: UIWindow?
    private var backgroundedAt: Date?
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.enabledKey: true, Self.graceKey: Self.defaultGrace])
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    var grace: TimeInterval { defaults.double(forKey: Self.graceKey) }

    /// Whether the device can authenticate its owner at all (a passcode is set).
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// "Face ID", "Touch ID", "Optic ID", or "Passcode" when there is no biometry.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    private var shouldLock: Bool { isEnabled && Self.isAvailable }

    /// Starts watching the app's life cycle; locks at once if the lock is on. Called once the
    /// scene is up (RootView's task), since the lock window needs a window scene.
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resignedActive() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enteredBackground() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameActive() }
            },
        ]
        if shouldLock {
            set(.locked)
            if UIApplication.shared.applicationState == .active { Task { await unlock() } }
        }
    }

    private func resignedActive() {
        // The Face ID prompt itself makes the app inactive: leave the lock as it is.
        if state == .unlocked { set(.covered) }
    }

    private func enteredBackground() {
        if state != .locked { backgroundedAt = Date() }
    }

    private func becameActive() {
        switch state {
        case .locked:
            if !isAuthenticating, failure == nil { Task { await unlock() } }
        case .covered:
            if shouldLock, let backgroundedAt, Date().timeIntervalSince(backgroundedAt) >= grace {
                set(.locked)
                Task { await unlock() }
            } else {
                set(.unlocked)
            }
            backgroundedAt = nil
        case .unlocked:
            break
        }
    }

    /// Asks the device owner to authenticate; unlocks on success.
    func unlock() async {
        guard state == .locked, !isAuthenticating else { return }
        guard Self.isAvailable else { set(.unlocked); return }   // passcode removed meanwhile
        isAuthenticating = true
        failure = nil
        defer { isAuthenticating = false }
        do {
            if try await Self.authenticate(reason: "Unlock Signet Go") { set(.unlocked) }
        } catch let error as LAError where error.code == .userCancel || error.code == .systemCancel || error.code == .appCancel {
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Authenticates the device owner for `reason`; Settings uses it before turning the lock off.
    static func authenticate(reason: String) async throws -> Bool {
        try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }

    private func set(_ new: State) {
        state = new
        if new == .unlocked { failure = nil }
        updateWindow()
    }

    private func updateWindow() {
        guard state != .unlocked else {
            window?.isHidden = true
            return
        }
        if window == nil {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
            else { return }
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            let host = UIHostingController(rootView: AppLockView(lock: self))
            host.view.backgroundColor = .clear
            window.rootViewController = host
            self.window = window
        }
        window?.isHidden = false
    }
}

/// What the lock window shows: the cover, and while locked an Unlock button.
struct AppLockView: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            Color(uiColor: .systemBackground).opacity(0.6).ignoresSafeArea()
            VStack(spacing: 20) {
                Image("SignetRing")
                    .resizable().scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                Text("Signet Go").font(.title.bold())
                if lock.state == .locked {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("Unlock", systemImage: AppLock.methodName == "Face ID" ? "faceid" : "lock.open")
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(lock.isAuthenticating)
                    if let failure = lock.failure {
                        Text(failure).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
            .padding(32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("AppLock")
    }
}
