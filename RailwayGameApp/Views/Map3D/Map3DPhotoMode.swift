import GameCore
import GamePresentation
import SwiftUI
import UIKit

/// Decision 981 (PHOTO-MODE): the 3D map's photo mode while it is open:
/// view state only (``PhotoTour``, GamePresentation), never the world's.
@MainActor
@Observable
final class Map3DPhotoModeState {
    /// Whether the mode is open: the map's own controls are put away.
    private(set) var isOpen = false
    /// Whether the mode's own buttons show; a tap on the map puts them
    /// away, for a picture of the map alone, and brings them back.
    private(set) var showsControls = true
    /// Which train and station the spots go to next.
    var tour = PhotoTour()
    /// From where the train the mode itself follows is seen
    /// (``PhotoTour/trainViews``); `nil` while it follows none, so a train
    /// the player was already following keeps their own view.
    private(set) var followView: Map3DFollow.View?
    /// What the mode last said (a picture saved, nothing to go to), for a
    /// few seconds.
    private(set) var notice: Notice?
    /// Counts the pictures saved, for the touch that says so.
    private(set) var saved = 0

    /// A line the mode says, with the symbol before it.
    struct Notice: Equatable {
        let id: Int
        let symbol: String
        let text: String
    }

    private var notices = 0

    func open(language: DisplayLanguage) {
        isOpen = true
        showsControls = true
        tour = PhotoTour()
        followView = nil
        say(language.text("Tap the map to hide these buttons, and again to bring them back.", "點一下地圖可以收起這些按鈕，再點一下叫回來。"), symbol: "hand.tap.fill")
    }

    /// Whether the mode itself started the follow it ends as it closes.
    @discardableResult
    func close() -> Bool {
        defer {
            isOpen = false
            followView = nil
            notice = nil
        }
        return followView != nil
    }

    func toggleControls() {
        showsControls.toggle()
    }

    func showControls() {
        showsControls = true
    }

    /// The mode follows a train from `view`, or (`nil`) no longer does.
    func follows(from view: Map3DFollow.View?) {
        followView = view
    }

    func say(_ text: String, symbol: String) {
        notices += 1
        notice = Notice(id: notices, symbol: symbol, text: text)
    }

    func sayNothing(after id: Int) {
        if notice?.id == id { notice = nil }
    }

    func savedPicture(language: DisplayLanguage) {
        saved += 1
        say(language.text("Saved to Photos", "已存到照片"), symbol: "checkmark.circle.fill")
    }
}

/// Decision 981: saves a picture to the Photos app, which asks the player
/// the first time (adding only, never reading their pictures:
/// `NSPhotoLibraryAddUsageDescription`). The system's answer comes back on
/// a thread of its own choosing, so it is taken off the main actor and
/// handed over.
@MainActor
final class Map3DPhotoSaver: NSObject {
    static let shared = Map3DPhotoSaver()

    /// Those waiting for an answer, the oldest first: the system answers
    /// in the order asked.
    private var waiting: [@MainActor (Bool) -> Void] = []

    /// Saves `picture`; `done` hears whether it was saved (not when the
    /// player has not allowed it).
    func save(_ picture: UIImage, done: @escaping @MainActor (Bool) -> Void) {
        waiting.append(done)
        UIImageWriteToSavedPhotosAlbum(picture, self, #selector(Map3DPhotoSaver.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc nonisolated private func image(_ image: UIImage, didFinishSavingWithError error: (any Error)?, contextInfo: UnsafeRawPointer?) {
        let saved = error == nil
        Task { @MainActor in self.answer(saved) }
    }

    private func answer(_ saved: Bool) {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst()(saved)
    }
}

/// Decision 981: the button that opens the photo mode, among the 3D map's
/// own controls; round, as the compass under it.
struct Map3DPhotoModeButton: View {
    let language: DisplayLanguage
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: "camera.viewfinder")
                .font(.headline)
                .frame(width: 44, height: 44)
                .glassBackground(in: Circle(), interactive: true)
        }
        .accessibilityLabel(Text(verbatim: language.text("Photo Mode", "拍照模式")))
        .accessibilityHint(Text(verbatim: language.text("Hides the controls, goes to places worth a picture and saves pictures to Photos.",
                                                        "收起控制項，一鍵到值得拍的地方，照片直接存到「照片」。")))
        .accessibilityIdentifier("map3D.photoMode.open")
    }
}

/// Decision 981: the photo mode's own controls, over the 3D map at its
/// lower edge: what it last said, the three spots, and under them the
/// close button, the shutter and the pause. A tap on the map puts all of
/// it away (``Map3DPhotoModeState/showsControls``).
struct Map3DPhotoBar: View {
    let state: Map3DPhotoModeState
    let session: GameSession
    /// Whether the scene is up, so there is somewhere to go.
    let isReady: Bool
    let go: (PhotoSpot) -> Void
    let shoot: () -> Void
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let language = session.language
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if state.showsControls {
                if let notice = state.notice {
                    Map3DPhotoNotice(notice: notice)
                        .transition(.pop(reduceMotion: reduceMotion))
                        .task(id: notice.id) {
                            try? await Task.sleep(for: .seconds(4))
                            if !Task.isCancelled { state.sayNothing(after: notice.id) }
                        }
                }
                VStack(spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        spots(language: language, named: true)
                        spots(language: language, named: false)
                    }
                    HStack(spacing: 0) {
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                                .glassBackground(in: Circle(), interactive: true)
                        }
                        .accessibilityLabel(Text(verbatim: language.text("Leave Photo Mode", "離開拍照模式")))
                        .accessibilityIdentifier("map3D.photoMode.close")
                        Spacer(minLength: 12)
                        Button(action: shoot) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.onPrimary)
                                .frame(width: 64, height: 64)
                                .background(Theme.primary, in: Circle())
                                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
                        }
                        .buttonStyle(TouchTargetButtonStyle(size: CGSize(width: 64, height: 64)))
                        .disabled(!isReady)
                        .accessibilityLabel(Text(verbatim: language.text("Take Photo", "拍照")))
                        .accessibilityHint(Text(verbatim: language.text("Saves the 3D view, without the buttons, to Photos.", "把現在的 3D 畫面存到「照片」，不含按鈕。")))
                        .accessibilityIdentifier("map3D.photoMode.shutter")
                        Spacer(minLength: 12)
                        Map3DPhotoPauseButton(session: session)
                    }
                }
                .frame(maxWidth: 420)
                .transition(.card(from: .bottom, reduceMotion: reduceMotion))
            } else {
                // Nothing drawn: the way back for VoiceOver, where a tap on
                // the map is not a gesture of its own.
                Button {
                    state.showControls()
                } label: {
                    Color.clear.frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text(verbatim: language.text("Show Photo Buttons", "顯示拍照按鈕")))
                .accessibilityIdentifier("map3D.photoMode.show")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(CGFloat(HUDMargins.edge))
        .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: state.showsControls)
        .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: state.notice?.id)
        .sensoryFeedback(.success, trigger: state.saved)
    }

    /// The three spots, each written out: a `ForEach`'s row closure in a
    /// `ViewThatFits` would be measured off the main thread (CRASH101).
    private func spots(language: DisplayLanguage, named: Bool) -> some View {
        HStack(spacing: 8) {
            spotButton(.train, language: language, named: named)
            spotButton(.station, language: language, named: named)
            spotButton(.skyline, language: language, named: named)
        }
    }

    private func spotButton(_ spot: PhotoSpot, language: DisplayLanguage, named: Bool) -> some View {
        Button {
            go(spot)
        } label: {
            Label {
                Text(verbatim: spot.text(in: language))
            } icon: {
                Image(systemName: Self.symbol(of: spot))
            }
            .labelStyle(Map3DPhotoSpotLabelStyle(named: named))
            .font(.headline)
            .lineLimit(1)
            .padding(.horizontal, named ? 14 : 0)
            .frame(minWidth: 44, minHeight: 44)
            .glassBackground(in: Capsule(), interactive: true)
        }
        .disabled(!isReady)
        .accessibilityLabel(Text(verbatim: spot.text(in: language)))
        .accessibilityHint(Text(verbatim: spot.hint(in: language)))
        .accessibilityIdentifier("map3D.photoMode.spot.\(spot.rawValue)")
    }

    static func symbol(of spot: PhotoSpot) -> String {
        switch spot {
        case .train: "tram.fill"
        case .station: "building.columns.fill"
        case .skyline: "building.2.fill"
        }
    }
}

/// A spot's button with its name, or where the names do not fit (the
/// largest type sizes on a narrow phone) its symbol alone.
private struct Map3DPhotoSpotLabelStyle: LabelStyle {
    let named: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            if named { configuration.title }
        }
    }
}

/// Decision 981: the photo mode's pause, so a train can be held where it
/// looks best; the map's own speeds are put away with the other controls.
private struct Map3DPhotoPauseButton: View {
    let session: GameSession

    var body: some View {
        let language = session.language
        let paused = session.world.clock.isPaused
        Button {
            session.togglePause()
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.headline)
                .frame(width: 44, height: 44)
                .glassBackground(in: Circle(), interactive: true)
        }
        .accessibilityLabel(Text(verbatim: paused ? language.text("Resume", "繼續") : language.text("Pause", "暫停")))
        .accessibilityHint(Text(verbatim: paused ? language.text("Lets the game run again.", "讓遊戲繼續跑。")
                                    : language.text("Holds the trains where they are for the picture.", "讓列車停在原地，方便拍照。")))
        .accessibilityIdentifier("map3D.photoMode.pause")
    }
}

/// Decision 981: what the photo mode last said, in a capsule over its
/// buttons.
private struct Map3DPhotoNotice: View {
    let notice: Map3DPhotoModeState.Notice

    var body: some View {
        Label {
            Text(verbatim: notice.text)
        } icon: {
            Image(systemName: notice.symbol)
        }
        .font(.subheadline.bold())
        .foregroundStyle(Theme.textPrimary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassBackground(in: Capsule())
        .accessibilityIdentifier("map3D.photoMode.notice")
    }
}
