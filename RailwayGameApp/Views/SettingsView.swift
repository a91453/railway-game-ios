import GameCore
import GamePresentation
import SwiftUI
import UIKit

/// The app's settings: the music and the sound effects on or off
/// (``GameAudio``), from the start screen and the game menu. Kept on the
/// device, never in a save. Under them, from a game, that game's own
/// settings (decision 154); the 3D city preview (decision 152); the app's
/// version and a way to report a problem (decision 127).
struct SettingsView: View {
    let audio: GameAudio
    /// What is in the game the settings were opened from
    /// (``GameSession/problemReportGame``), for a problem report; `nil`
    /// from the start screen.
    var game: String? = nil
    /// The game the settings were opened from, for its own settings
    /// (decision 154: holidays and other events); `nil` from the start
    /// screen.
    var session: GameSession? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showsCityView = false

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
                if let session {
                    eventsSection(session)
                }
                previewSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .fullScreenCover(isPresented: $showsCityView) {
                CityView3D()
            }
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

    /// Decision 154: how strongly the game's holidays (and later its other
    /// events) bite, kept in the game's save, and whose holidays they are.
    private func eventsSection(_ session: GameSession) -> some View {
        let language = session.language
        let levels: [DisruptionLevel?] = [nil, .light, .standard]
        return Section {
            Picker(selection: Binding(get: { session.world.disruptions?.level }, set: { session.setDisruptionLevel($0) })) {
                ForEach(levels, id: \.self) { level in
                    Text(verbatim: level?.title(in: language) ?? language.text("Off", "關")).tag(level)
                }
            } label: {
                Label {
                    Text(verbatim: language.text("Holidays and events", "連假與事件"))
                } icon: {
                    Image(systemName: "calendar")
                }
            }
            .accessibilityIdentifier("settings.disruptions")
            if let country = session.world.disruptions?.country {
                LabeledContent {
                    Text(verbatim: holidayCountryName(country, in: language))
                } label: {
                    Text(verbatim: language.text("Public holidays of", "國定假日"))
                }
            }
        } header: {
            Text(verbatim: language.text("This game", "這一局"))
        } footer: {
            Text(verbatim: language.text(
                "Public holidays raise demand on every line, announced a week ahead. Rain lowers it, a typhoon (announced days ahead) cuts it at the stations in its path, and fuel spells change the day's energy cost. Light is half as strong as Standard. Kept in this game's save.",
                "國定假日時各線需求增加，一週前公布。下雨時需求減少，颱風（幾天前預警）讓路徑上的車站需求大減，油電價格偶爾漲跌、影響能源費。「輕」的影響是「標準」的一半。設定存在這一局的存檔裡。"
            ))
        }
    }

    /// Decision 152: the 3D city view, a preview of what the game's 3D may
    /// look like (``CityView3D``).
    private var previewSection: some View {
        let language = DisplayLanguage.app
        return Section {
            Button {
                showsCityView = true
            } label: {
                Label {
                    Text(verbatim: language.text("3D City: Kaohsiung Station", "3D 城市：高雄車站"))
                } icon: {
                    Image(systemName: "building.2")
                }
            }
            .accessibilityIdentifier("settings.cityView")
        } header: {
            Text(verbatim: language.text("Preview", "試作"))
        } footer: {
            Text(verbatim: language.text(
                "A try-out of a 3D city: the real buildings, roads and parks round Kaohsiung Station, drawn by the Procedural Tokyo renderer. It is not part of your game yet: the cars and the light are its own. Drag to move, pinch to zoom, two fingers to turn.",
                "3D 城市的試作：高雄車站周圍真實的建物、道路與公園，用 Procedural Tokyo 的繪製程式畫出來。還沒有接上你的遊戲：車流與光線都是它自己的。拖曳移動、兩指縮放、兩指旋轉。"
            ))
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
