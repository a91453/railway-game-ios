import GameCore

// The tutorial's controls (Stage C5; see Tutorial.swift): start it, or
// start it again from the first step, from the start screen or the game
// menu; Back, Next (Done on the last step) and Skip on its card. None of
// them changes the world.

extension GameSession {
    /// Shows the tutorial from its first step: the reference's
    /// `startTutorial`, and starting it again from the game menu.
    public func startTutorial() {
        tutorial = Tutorial(steps: Tutorial.standardSteps, over: world)
    }

    /// Whether the player has done what the step on screen asks (the
    /// reference's `_tutorialStepActionDone`), read from the world and the
    /// active tool; `false` without a tutorial. Next waits for it.
    public var isTutorialStepDone: Bool {
        tutorial?.isStepDone(in: world, tool: tool) ?? false
    }

    /// Next: the following step, or, on the last step, Done, which ends the
    /// tutorial. Does nothing until the step on screen is done.
    public func showNextTutorialStep() {
        guard var shown = tutorial, isTutorialStepDone else { return }
        if shown.isLastStep {
            tutorial = nil
        } else {
            shown.show(shown.index + 1, over: world)
            tutorial = shown
        }
    }

    /// Back: the step before. Does nothing on the first step.
    public func showPreviousTutorialStep() {
        guard var shown = tutorial, !shown.isFirstStep else { return }
        shown.show(shown.index - 1, over: world)
        tutorial = shown
    }

    /// Skip: ends the tutorial at any step (the reference's
    /// `dismissTutorial`).
    public func skipTutorial() {
        tutorial = nil
    }

    /// The player moved the map: pinched, dragged or tapped a zoom button
    /// (Stage E1). The camera is the map view's own state, so the view
    /// calls this for the tutorial's ``TutorialGoal/moveMap``. Changes the
    /// session only the first time on such a step, so calling it on every
    /// frame of a gesture costs nothing.
    public func mapDidMove() {
        guard var shown = tutorial, shown.awaitsMapMove else { return }
        shown.noteMapMoved()
        tutorial = shown
    }
}
