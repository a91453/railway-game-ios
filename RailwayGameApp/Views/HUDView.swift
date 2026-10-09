import GameCore
import GamePresentation
import SwiftUI
import UniformTypeIdentifiers

/// Cash (which opens the economy panel), game time, speed controls and the
/// game menu (Stage C4: save, export, back to the start screen), in the
/// status pill at the top of the screen (``ContentView``, decision 106);
/// the lines are in the dock. Everything shown is read from the world, so
/// it updates as soon as a command or a tick changes it. Its controls have
/// no backgrounds of their own: the pill it sits in is glass.
struct HUDView: View {
    let session: GameSession
    let launcher: GameLauncher
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        // One row, as wide as what it shows, when it fits; otherwise cash
        // and time stack; with the largest text the time gets a row of its
        // own rather than being cut short ("Day 2 · 07…"), and the cash is
        // never cut short ("$ 3,0…").
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                cash
                time
                SpeedControl(session: session)
                gameMenu
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    cash
                    time
                }
                SpeedControl(session: session)
                gameMenu
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    cash
                    SpeedControl(session: session)
                    gameMenu
                }
                time
                    .minimumScaleFactor(0.75)
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
    }

    /// Saving, exporting the game as a file, the tutorial, the settings
    /// (music and sound effects), and going back to the start screen,
    /// which autosaves first.
    private var gameMenu: some View {
        Menu {
            Button {
                launcher.saveCurrentGame()
            } label: {
                Label("Save Game", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("menu.saveGame")
            ShareLink(item: ExportedSave(world: session.world), preview: SharePreview(Text("Along the Line save"))) {
                Label("Export Save", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button {
                session.startTutorial()
            } label: {
                Label("Tutorial", systemImage: "hand.point.up.left")
            }
            .accessibilityIdentifier("menu.tutorial")
            // Decision 86: a game with a challenge shows its goals.
            if session.world.scenario != nil {
                Button {
                    screen.panel = .goals
                } label: {
                    Label {
                        Text(verbatim: session.language.text("Goals", "目標"))
                    } icon: {
                        Image(systemName: "flag.checkered")
                    }
                }
                .accessibilityIdentifier("menu.goals")
            }
            Divider()
            Button {
                screen.panel = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("menu.settings")
            Divider()
            Button {
                launcher.returnToStart()
            } label: {
                Label("Back to Start", systemImage: "house")
            }
            .accessibilityIdentifier("menu.backToStart")
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 38, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Game menu")
        .accessibilityHint("Saves the game, exports it as a file, opens the tutorial or the settings, or goes back to the start screen.")
        .accessibilityIdentifier("hud.menu")
        .tutorialTarget(.gameMenu)
    }

    /// The balance in dollars; it opens the economy panel.
    private var cash: some View {
        let text = session.world.economy.balance.moneyText
        let isNegative = session.world.economy.balance < .zero
        return Button {
            screen.panel = .economy
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "banknote.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isNegative ? Theme.error : Theme.success)
                Text(text)
                    .foregroundStyle(isNegative ? Theme.error : Theme.textPrimary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Decision 117: what just came in, under the cash.
        .overlay(alignment: .bottom) {
            IncomeFloat(pulse: session.incomePulse)
        }
        .accessibilityLabel("Cash \(text)")
        .accessibilityHint("Shows fares, running costs and the ledger.")
    }

    private var time: some View {
        let text = session.world.clock.displayText(in: session.language)
        return HStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.primary)
            Text(text)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .accessibilityLabel("Game time \(text)")
    }
}

/// Pause or play, and a menu of the speeds from real time up (Stage W2a),
/// labelled with the speed the game runs at. Everything is read from the
/// world's clock.
private struct SpeedControl: View {
    let session: GameSession

    var body: some View {
        let clock = session.world.clock
        let language = session.language
        HStack(spacing: 4) {
            Button {
                session.togglePause()
            } label: {
                Image(systemName: clock.isPaused ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 38, height: 32)
            }
            .buttonStyle(ThemeSelectableButtonStyle(isActive: clock.isPaused))
            .accessibilityLabel(clock.isPaused ? "Resume" : "Pause")
            Menu {
                ForEach(GameSpeed.allCases.filter { $0 != .paused }, id: \.self) { speed in
                    Button {
                        session.setSpeed(speed)
                    } label: {
                        if speed == clock.speed {
                            Label(speed.label(in: language), systemImage: "checkmark")
                        } else {
                            Text(speed.label(in: language))
                        }
                    }
                    .accessibilityLabel(speed.accessibilityName(in: language))
                }
            } label: {
                HStack(spacing: 4) {
                    if clock.isPaused {
                        Circle()
                            .fill(Theme.warning)
                            .frame(width: 6, height: 6)
                    }
                    Text(clock.runningSpeed.label(in: language))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
                .padding(.horizontal, 8)
                .frame(minWidth: 48, minHeight: 32)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Speed: \(clock.runningSpeed.accessibilityName(in: language))")
            .accessibilityHint("Chooses how fast game time runs.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game speed")
        .tutorialTarget(.speedControl)
    }
}

/// The game as a save file to share (Stage C4, the reference's "导出本地存档"),
/// written when the player shares it.
private struct ExportedSave: Transferable {
    let world: GameWorld

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { save in
            SentTransferredFile(try SaveLibrary.exportFile(for: save.world, at: Date()))
        }
    }
}
