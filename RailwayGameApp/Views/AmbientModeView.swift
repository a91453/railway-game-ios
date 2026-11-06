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
    /// Decision 606: the real timetable's train the 3D map follows; `nil`
    /// for any other shot.
    var realTrain: RealTrainID?
    /// Decision 606: what that train is and where it goes, faint in the
    /// corner for its first seconds (``AmbientDirector/realCaptionSeconds``).
    var cornerCaption: String?
    var showsCornerCaption = false
    /// Decision 606: whether the 3D map has found the real train to
    /// follow, from when the corner line shows.
    var realTrainSeen = false
    /// Decision 606: a real train the 3D map could not find to follow
    /// (in a tunnel, past the scene), which the director passes over.
    var lostRealTrain: RealTrainID?
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
        session.setFollowingRealTrain(false)
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
    /// Decision 339: the real timetables' trains shown; decision 606: the
    /// idle mode follows them only then.
    @AppStorage(MapAmbienceSettings.realTrainsKey) private var showsRealTrains = true

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
        // Decision 606: the real trains on the map, worked out once.
        let realTrains = await workOutRealTrains()
        while !Task.isCancelled, screen.ambient != nil {
            // Read each time: Reduce Motion may be turned on meanwhile.
            let allows3D = shows3D && !UIAccessibility.isReduceMotionEnabled
            var cast = AmbientDirector.Cast(world: session.world)
            if let realTrains, showsRealTrains {
                let clock = RealTrainClock(world: session.world, time: Date.timeIntervalSinceReferenceDate)
                let lost = screen.ambient?.lostRealTrain
                cast.realTrains = realTrains.candidates(at: clock.second(at: 0, glides: false), on: clock.today, dayBefore: clock.dayBefore)
                    .filter { $0.id != lost }
            }
            if let shot = director.update(cast: cast, now: Date.timeIntervalSinceReferenceDate, allows3D: allows3D) {
                await cut(to: shot, veiled: !first, realTrains: realTrains)
                first = false
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Decision 606: the real lines on a real-world map and their trains,
    /// as the 3D map draws them (but the lines the player bought), off the
    /// main actor; `nil` on a map of no real place or with them hidden.
    private func workOutRealTrains() async -> AmbientRealTrains? {
        guard showsRealTrains, let railways = session.railways, let operations = railways.operations,
              let frame = RealWorldFrame(world: session.world) else { return nil }
        let bounds = session.world.bounds
        let bought = Set(session.world.acquisitions.map(\.realLine))
        return await Task.detached(priority: .utility) { () -> AmbientRealTrains? in
            let traffic = RealTrainTraffic(operations: operations, frame: frame, bounds: bounds, bought: bought)
            return traffic.lines.isEmpty ? nil : AmbientRealTrains(traffic: traffic, operations: operations, frame: frame, railways: railways)
        }.value
    }

    /// The site's `fadeSwitch`: the veil comes down, the shot changes
    /// behind it, the veil lifts; the first shot without it (`_ambientFresh`).
    private func cut(to shot: AmbientDirector.Shot, veiled: Bool, realTrains: AmbientRealTrains?) async {
        let rule = MotionRule.ambientCut.running(reduceMotion: UIAccessibility.isReduceMotionEnabled) ?? .ambientCut
        if veiled {
            withAnimation(rule.animation) { screen.ambient?.veiled = true }
            // Dark a moment longer than the fade, as the site's 0.8 s after
            // its 0.7 s.
            try? await Task.sleep(for: .seconds(rule.seconds + 0.1))
        }
        guard screen.ambient != nil else { return }
        await show(shot, realTrains: realTrains)
        withAnimation(rule.animation) { screen.ambient?.veiled = false }
    }

    private func show(_ shot: AmbientDirector.Shot, realTrains: AmbientRealTrains?) async {
        let world = session.world
        screen.ambient?.caption = AmbientDirector.caption(of: shot.subject, in: world, language: session.language)
        // Decision 606: the 3D map round a real train is built there, not
        // round the player's train next.
        let afterRealTrain = screen.ambient?.realTrain != nil
        screen.ambient?.realTrain = nil
        screen.ambient?.realTrainSeen = false
        screen.ambient?.cornerCaption = nil
        screen.ambient?.showsCornerCaption = false
        switch shot.subject {
        case .realTrain(let id):
            // Decision 606: the 3D map opened afresh over the real train,
            // its scene built round it, following it.
            session.stopFollowingTrain()
            let clock = RealTrainClock(world: world, time: Date.timeIntervalSinceReferenceDate)
            let second = clock.second(at: 0, glides: false)
            guard let realTrains, let location = realTrains.location(of: id, at: second, on: clock.today, dayBefore: clock.dayBefore)
            else {
                session.setFollowingRealTrain(false)
                return
            }
            // Held to 10× from here, as a train of the player's on the 3D
            // map (decision 360): at 600× it would be gone in a second.
            session.setFollowingRealTrain(true)
            close3D()
            // A moment for the closed map (a full-screen cover) to go before
            // it opens again: one presented while it goes would not show.
            try? await Task.sleep(for: .milliseconds(500))
            guard screen.ambient != nil else { return }
            if case .map3D(let view) = shot.stage { screen.ambient?.view3D = view }
            screen.ambient?.realTrain = id
            open3D(location)
            showCornerCaption(realTrains.caption(of: id, at: second, on: clock.today, dayBefore: clock.dayBefore, language: session.language))
        case .train(let id):
            session.followTrain(id)
            session.setFollowingRealTrain(false)
            if case .map3D(let view) = shot.stage {
                screen.ambient?.view3D = view
                if afterRealTrain {
                    close3D()
                    try? await Task.sleep(for: .milliseconds(500))
                    guard screen.ambient != nil else { return }
                }
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
            session.setFollowingRealTrain(false)
            screen.ambient?.view3D = nil
            close3D()
            if let region = AmbientDirector.region(of: shot.subject, in: world) {
                session.lookOver(region)
            }
        }
    }

    /// Decision 606: `caption` faint in the corner from when the 3D map
    /// shows the train, gone again ``AmbientDirector/realCaptionSeconds``
    /// later; with Reduce Motion it comes and goes at once.
    private func showCornerCaption(_ caption: String?) {
        guard let caption else { return }
        screen.ambient?.cornerCaption = caption
        screen.ambient?.showsCornerCaption = true
        Task { @MainActor in
            while screen.ambient?.cornerCaption == caption, screen.ambient?.realTrainSeen == false {
                try? await Task.sleep(for: .milliseconds(500))
            }
            try? await Task.sleep(for: .seconds(AmbientDirector.realCaptionSeconds))
            guard screen.ambient?.cornerCaption == caption else { return }
            let reduce = UIAccessibility.isReduceMotionEnabled
            withAnimation(reduce ? nil : MotionRule.ambientCut.animation) { screen.ambient?.showsCornerCaption = false }
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
        // Decision 606: what the real train followed is and where it goes,
        // faint in the top corner for its first seconds; read on its own,
        // and a tap on it ends the mode as anywhere else.
        .overlay(alignment: .topLeading) {
            if let corner = ambient?.cornerCaption, ambient?.showsCornerCaption == true, ambient?.realTrainSeen == true,
               ambient?.veiled == false {
                Text(verbatim: corner)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(CGFloat(HUDMargins.edge))
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("ambient.realTrain")
            }
        }
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
