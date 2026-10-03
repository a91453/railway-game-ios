import GameCore
import GamePresentation
import SwiftUI
import UniformTypeIdentifiers

/// Cash (which opens the economy panel), game time, speed controls, the
/// button that opens the lines panel and the game menu (Stage C4: save,
/// export, back to the start screen). Everything shown is read from the
/// world, so it updates as soon as a command or a tick changes it.
struct HUDView: View {
    let session: GameSession
    let launcher: GameLauncher
    @State private var showsLines = false
    @State private var showsEconomy = false

    var body: some View {
        // One row when it fits (iPad, sidebar), otherwise cash and time stack.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                cash
                time
                Spacer(minLength: 12)
                linesButton
                SpeedControl(session: session)
                gameMenu
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    cash
                    time
                }
                Spacer(minLength: 8)
                linesButton
                SpeedControl(session: session)
                gameMenu
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .sheet(isPresented: $showsEconomy) {
            EconomyPanel(session: session)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsLines) {
            LinesPanel(session: session)
                .presentationDetents([.medium, .large])
                // The map stays usable behind the half-height sheet, so
                // stations can be selected for a new line.
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    private var linesButton: some View {
        Button {
            showsLines = true
        } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.bold))
                .frame(width: 44, height: 32)
        }
        .buttonStyle(SelectableButtonStyle(isActive: showsLines))
        .accessibilityLabel("Lines")
        .accessibilityHint("Shows the service lines and their timetables.")
        .tutorialTarget(.linesButton)
    }

    /// Saving, exporting the game as a file and going back to the start
    /// screen, which autosaves first.
    private var gameMenu: some View {
        Menu {
            Button {
                launcher.saveCurrentGame()
            } label: {
                Label("Save Game", systemImage: "square.and.arrow.down")
            }
            ShareLink(item: ExportedSave(world: session.world), preview: SharePreview(Text("Railway Game save"))) {
                Label("Export Save", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button {
                session.startTutorial()
            } label: {
                Label("Tutorial", systemImage: "hand.point.up.left")
            }
            .accessibilityIdentifier("menu.tutorial")
            Divider()
            Button {
                launcher.returnToStart()
            } label: {
                Label("Back to Start", systemImage: "house")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.bold))
                .frame(width: 44, height: 32)
        }
        .accessibilityLabel("Game menu")
        .accessibilityHint("Saves the game, exports it as a file, or goes back to the start screen.")
        .tutorialTarget(.gameMenu)
    }

    /// The balance in dollars; it opens the economy panel.
    private var cash: some View {
        let text = session.world.economy.balance.moneyText
        return Button {
            showsEconomy = true
        } label: {
            Label(text, systemImage: "banknote")
                .foregroundStyle(session.world.economy.balance < .zero ? Color.red : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cash \(text)")
        .accessibilityHint("Shows fares, running costs and the ledger.")
    }

    private var time: some View {
        let text = session.world.clock.displayText(in: session.language)
        return Label(text, systemImage: "clock")
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
                    .frame(width: 44, height: 32)
            }
            .buttonStyle(SelectableButtonStyle(isActive: clock.isPaused))
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
                Text(clock.runningSpeed.label(in: language))
                    .font(.subheadline.weight(.bold))
                    .frame(minWidth: 56, minHeight: 32)
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
