import GamePresentation
import SwiftUI
import UIKit

/// The app's settings: the music and the sound effects on or off
/// (``GameAudio``), from the start screen and the game menu. Kept on the
/// device, never in a save. Under them, the app's version and a way to
/// report a problem (decision 127).
struct SettingsView: View {
    let audio: GameAudio
    /// What is in the game the settings were opened from
    /// (``GameSession/problemReportGame``), for a problem report; `nil`
    /// from the start screen.
    var game: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { audio.musicOn }, set: { audio.setMusicOn($0) })) {
                        Label("Music", systemImage: "music.note")
                    }
                    .accessibilityIdentifier("settings.music")
                    Toggle(isOn: Binding(get: { audio.soundsOn }, set: { audio.setSoundsOn($0) })) {
                        Label("Sound Effects", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("settings.sounds")
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Sound effects: a chime when a train arrives, a rail joint when track is built and a whoosh when you change tools. In silent mode the game makes no sound.")
                }
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings.done")
                }
            }
        }
    }

    /// Decision 127: the version testers quote, and a note to send about a
    /// problem, through the share sheet to wherever the player chooses.
    private var aboutSection: some View {
        let language = DisplayLanguage.app
        let report = problemReport
        return Section {
            LabeledContent {
                Text(verbatim: report.versionText)
                    .textSelection(.enabled)
            } label: {
                Label {
                    Text(verbatim: language.text("Version", "版本"))
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
            .accessibilityIdentifier("settings.version")
            ShareLink(item: report.text(in: language), subject: Text(verbatim: report.subject(in: language))) {
                Label {
                    Text(verbatim: language.text("Report a Problem", "回報問題"))
                } icon: {
                    Image(systemName: "exclamationmark.bubble")
                }
            }
            .accessibilityIdentifier("settings.report")
        } header: {
            Text(verbatim: language.text("About", "關於"))
        } footer: {
            Text(verbatim: language.text(
                "Report a Problem writes a note with the version, your device and, from a game, what is in it, for Mail, Messages or any app you choose. Nothing is sent until you send it. Testing in TestFlight? You can also take a screenshot and share it with the developer from there.",
                "「回報問題」會寫好一則附上版本、裝置（在遊戲中開啟時還有遊戲的狀態）的訊息，由你選擇用郵件、訊息或其他 App 傳送；你按下傳送前不會送出任何東西。用 TestFlight 測試時，也可以截圖後直接分享給開發者。"
            ))
        }
    }

    /// The note for this app, system and device.
    private var problemReport: ProblemReport {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return ProblemReport(
            version: version, build: build, system: "\(device.systemName) \(device.systemVersion)", device: Self.modelIdentifier, game: game
        )
    }

    /// The device's model identifier ("iPhone17,1"; "arm64" on the
    /// Simulator): which model, without anything about its owner.
    private static var modelIdentifier: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
