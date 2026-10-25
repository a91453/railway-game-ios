import Foundation
import GameCore
import GamePresentation
import SwiftUI
import UIKit

/// Decision 414: the idle mode while it runs (放空模式), kept in
/// ``GameScreenState/ambient``: view state only, never the world's.
struct AmbientScreen: Equatable {
    /// The 3D view the shot follows its train from; `nil` on the 2D map.
    var view3D: Map3DFollow.View?
    /// What the shot shows, under it.
    var caption: String?
    /// Whether the dark veil is down, between two shots.
    var veiled = false
    /// Whether the line saying how to come back shows: the first seconds.
    var showsHint = true
    /// Whether the game was paused when the mode started: it runs while
    /// the player watches, and is paused again when they come back.
    let resumedFromPause: Bool
}

/// Decision 414: starting and ending the idle mode.
@MainActor
enum AmbientMode {
    /// Puts the controls away and lets the director move the camera; a
    /// paused game runs. Not in the tutorial, whose steps wait for the
    /// player; with nothing built yet it rests on the map as it is.
    static func start(session: GameSession, screen: GameScreenState) {
        guard screen.ambient == nil, session.tutorial == nil else { return }
        screen.panel = nil
        let paused = session.world.clock.isPaused
        if paused { session.togglePause() }
        screen.ambient = AmbientScreen(resumedFromPause: paused)
    }

    /// Back to the game where the camera is: the controls return, the
    /// follow ends, the 3D map closes at once, a game paused before is
    /// paused again.
    static func end(session: GameSession, screen: GameScreenState) {
        guard let ambient = screen.ambient else { return }
        screen.ambient = nil
        session.stopFollowingTrain()
        if screen.showsMap3D {
            var cut = Transaction()
            cut.disablesAnimations = true
            withTransaction(cut) { screen.showsMap3D = false }
        }
        if ambient.resumedFromPause, !session.world.clock.isPaused { session.togglePause() }
    }
}

/// Decision 414: over the whole game while the idle mode runs: catches the
/// tap that ends it, draws the veil between shots and the line saying
/// what is shown, and runs the director (``AmbientDirector``) about once a
/// second.
struct AmbientOverlay: View {
    let session: GameSession
    let screen: GameScreenState
    /// The 3D map is on in Settings (decision 365).
    let shows3D: Bool
    /// Opens the 3D map over `point` (world units), following the train.
    let open3D: (_ point: WorldCoordinate) -> Void

    var body: some View {
        AmbientCurtain(screen: screen, language: session.language) {
            AmbientMode.end(session: session, screen: screen)
        }
        .task { await direct() }
        // The screen stays awake while it runs (the site's `acquireWakeLock`).
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(MotionRule.ambientCut.animation) { screen.ambient?.showsHint = false }
        }
    }

    private func direct() async {
        var director = AmbientDirector(seed: UInt64(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1_000)))
        var first = true
        while !Task.isCancelled, screen.ambient != nil {
            // Read each time: Reduce Motion may be turned on meanwhile.
            let allows3D = shows3D && !UIAccessibility.isReduceMotionEnabled
            let cast = AmbientDirector.Cast(world: session.world)
            if let shot = director.update(cast: cast, now: Date.timeIntervalSinceReferenceDate, allows3D: allows3D) {
                await cut(to: shot, veiled: !first)
                first = false
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// The site's `fadeSwitch`: the veil comes down, the shot changes
    /// behind it, the veil lifts; the first shot without it (`_ambientFresh`).
    private func cut(to shot: AmbientDirector.Shot, veiled: Bool) async {
        let rule = MotionRule.ambientCut.running(reduceMotion: UIAccessibility.isReduceMotionEnabled) ?? .ambientCut
        if veiled {
            withAnimation(rule.animation) { screen.ambient?.veiled = true }
            // Dark a moment longer than the fade, as the site's 0.8 s after
            // its 0.7 s.
            try? await Task.sleep(for: .seconds(rule.seconds + 0.1))
        }
        guard screen.ambient != nil else { return }
        show(shot)
        withAnimation(rule.animation) { screen.ambient?.veiled = false }
    }

    private func show(_ shot: AmbientDirector.Shot) {
        let world = session.world
        screen.ambient?.caption = AmbientDirector.caption(of: shot.subject, in: world, language: session.language)
        switch shot.subject {
        case .train(let id):
            session.followTrain(id)
            if case .map3D(let view) = shot.stage {
                screen.ambient?.view3D = view
                if !screen.showsMap3D, let position = world.train(id: id)?.position,
                   let location = world.location(of: position)?.position {
                    open3D(location)
                }
            } else {
                screen.ambient?.view3D = nil
                close3D()
            }
        case .station, .line:
            session.stopFollowingTrain()
            screen.ambient?.view3D = nil
            close3D()
            if let region = AmbientDirector.region(of: shot.subject, in: world) {
                session.lookOver(region)
            }
        }
    }

    private func close3D() {
        guard screen.showsMap3D else { return }
        var cut = Transaction()
        cut.disablesAnimations = true
        withTransaction(cut) { screen.showsMap3D = false }
    }
}

/// Decision 414: the idle mode's layer over the 2D or the 3D map: the
/// veil, the caption at the bottom and, for its first seconds, how to come
/// back; a tap anywhere ends the mode.
struct AmbientCurtain: View {
    let screen: GameScreenState
    let language: DisplayLanguage
    let end: () -> Void

    var body: some View {
        let ambient = screen.ambient
        let showsHint = ambient?.showsHint == true
        ZStack(alignment: .bottom) {
            // Taps anywhere, over a map that takes none meanwhile.
            Color.black.opacity(ambient?.veiled == true ? 1 : 0.001)
                .ignoresSafeArea()
            VStack(spacing: 6) {
                if showsHint {
                    Text(verbatim: language.text("Tap the screen to come back.", "碰一下螢幕就回來。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                if let caption = ambient?.caption, ambient?.veiled == false {
                    Text(verbatim: caption)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .opacity(showsHint || ambient?.caption != nil ? 1 : 0)
            .padding(.bottom, CGFloat(HUDMargins.edge))
            .padding(.horizontal, CGFloat(HUDMargins.edge))
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: end)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: language.text("Idle mode", "放空模式")))
        .accessibilityHint(Text(verbatim: language.text("Tap to come back to the game.", "點兩下回到遊戲。")))
        .accessibilityAction { end() }
        .accessibilityIdentifier("ambient.curtain")
    }
}

extension View {
    /// Decision 414: put away while the idle mode runs: not drawn, not
    /// touched, and not read aloud (SwiftUI leaves a view of no opacity
    /// out of VoiceOver); kept in place, so nothing moves round it. No
    /// `accessibilityHidden(hidden)`: with it, even when `false`, the UI
    /// tests found neither the map nor its zoom buttons hittable (#1261's
    /// first run), as if the controls had become one element over them.
    func ambientHidden(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
    }
}
