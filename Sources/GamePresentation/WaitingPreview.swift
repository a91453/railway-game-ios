// Decision 590: previews that run a command on a copy of the world are not
// worked out inside a view update.
//
// A preview such as ``GameSession/lineOpeningPreview`` tries the command it
// prices on copies of the world: `GameWorld` is about 2 KB, and the
// functions on that path hold tens of copies each (about 140 KB of stack in
// an optimised build). Asked for from a map view's body, it ran on top of
// SwiftUI's view update and took the main thread's stack past its end
// (TestFlight 112.1, "Thread stack size exceeded" while picking a new
// line's stations). In the app, such a preview asked for while it is not
// worked out yet answers "not yet" and is worked out on the main actor's
// next turn, from a shallow stack; the view reads it again then.

/// A preview that can wait for the main actor's next turn.
enum WaitingPreview: Hashable {
    case lineOpening
    case lineConfirmation
    /// The network tool's stretch drawn (``GameSession/networkDraftPreview``).
    case networkDraft
    /// The heights that let a refused stretch be built (decision 629,
    /// ``GameSession/networkHeightCard``).
    case networkHeightFixes
    /// The platform tool's station layout (``GameSession/networkStationLayoutPreview``).
    case stationLayout
    /// The crossovers of a platform on both tracks (``GameSession/networkPlatformCrossovers``).
    case platformCrossovers
    /// The track card's upgrade (``GameSession/trackUpgradeDraft``).
    case trackUpgrade
}

extension GameSession {
    /// Whether `preview` waits for the main actor's next turn instead of
    /// being worked out now: in the app's sessions
    /// (``worksOutPreviewsOnTheNextTurn``), where `workOut` then runs on
    /// the next turn, once however often it is asked for meanwhile, and the
    /// views that asked look again. Elsewhere `false`, to be worked out at
    /// once.
    func waits(for preview: WaitingPreview, workOut: @escaping @MainActor (GameSession) -> Void) -> Bool {
        guard worksOutPreviewsOnTheNextTurn else { return false }
        // Observed, so that the view asking now looks again once it is in.
        _ = previewsWorkedOutLater
        guard previewsWaiting.insert(preview).inserted else { return true }
        Task { [weak self] in
            guard let self else { return }
            previewsWaiting.remove(preview)
            workOut(self)
            previewsWorkedOutLater &+= 1
        }
        return true
    }

    /// Whether `preview` is waiting for the main actor's next turn.
    func isWaiting(for preview: WaitingPreview) -> Bool {
        previewsWaiting.contains(preview)
    }

    /// Returns once the previews waiting for the next turn are in (tests).
    func waitingPreviewsSettled() async {
        while !previewsWaiting.isEmpty { await Task.yield() }
    }
}
