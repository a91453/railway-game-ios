import GameKit
import GamePresentation
import Observation
import UIKit

/// The app's link to Game Center (decision 396): signs the player in in the
/// background and sends what GamePresentation's ``GameCenterReport`` says.
/// It never blocks the start: iOS's sign-in screen is kept and shown only
/// when the player taps "Sign in to Game Center", and a player who is not
/// signed in, or declined, plays on with nothing said. What to send, and
/// when, is decided in GamePresentation; this only calls GameKit.
@MainActor
@Observable
final class GameCenterLink {
    /// Whether the player is signed in to Game Center.
    private(set) var isSignedIn = false
    /// Whether iOS handed a sign-in screen to show when the player asks.
    private(set) var canSignIn = false

    @ObservationIgnored private var signInScreen: UIViewController?
    @ObservationIgnored private var ledger = GameCenterLedger()
    @ObservationIgnored private weak var launcher: GameLauncher?

    /// Whether the links beside the achievements are shown.
    var isAvailable: Bool {
        isSignedIn || canSignIn
    }

    /// Starts signing in and reports `launcher`'s achievements and results
    /// from then on.
    func start(launcher: GameLauncher) {
        self.launcher = launcher
        launcher.reportToGameCenter = { [weak self] report in self?.send(report) }
        GKLocalPlayer.local.authenticateHandler = { @Sendable screen, _ in
            Task { @MainActor in self.authenticated(screen) }
        }
    }

    private func authenticated(_ screen: UIViewController?) {
        signInScreen = screen
        canSignIn = screen != nil
        let signedIn = GKLocalPlayer.local.isAuthenticated
        guard signedIn != isSignedIn else { return }
        isSignedIn = signedIn
        // A new player, or the same one again: everything once more.
        ledger = GameCenterLedger()
        if signedIn, let launcher { send(launcher.gameCenterReport()) }
    }

    private func send(_ report: GameCenterReport) {
        guard isSignedIn else { return }
        let changes = ledger.changes(in: report)
        if !changes.achievements.isEmpty {
            let achievements = changes.achievements.map { id, percent in
                let achievement = GKAchievement(identifier: id)
                achievement.percentComplete = Double(percent)
                // The game says so itself, on its status line.
                achievement.showsCompletionBanner = false
                return achievement
            }
            GKAchievement.report(achievements) { _ in }
        }
        if let score = changes.score {
            GKLeaderboard.submitScore(
                score.days, context: score.riders, player: GKLocalPlayer.local, leaderboardIDs: [score.leaderboardID]
            ) { _ in }
        }
    }

    /// Shows iOS's sign-in screen, kept from the start.
    func signIn() {
        guard let signInScreen else { return }
        present(signInScreen)
    }

    /// Opens Game Center's leaderboards, where this week's is.
    func showLeaderboards() {
        GKAccessPoint.shared.trigger(state: .leaderboards) {}
    }

    /// Opens Game Center's achievements.
    func showAchievements() {
        GKAccessPoint.shared.trigger(state: .achievements) {}
    }

    private func present(_ screen: UIViewController) {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard var top = window?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(screen, animated: true)
    }
}
