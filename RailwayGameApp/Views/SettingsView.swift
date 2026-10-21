import GameCore
import GamePresentation
import SwiftUI
import UIKit

/// The app's settings: the music and the sound effects on or off, and
/// their three volumes (``GameAudio``, decision 219), from the start
/// screen and the game menu. Kept on the
/// device, never in a save. Under them, from a game, that game's own
/// settings (decision 154); the 3D city preview (decision 152); the app's
/// version and a way to report a problem (decision 127).
struct SettingsView: View {
    let audio: GameAudio
    /// What is in the game the settings were opened from
    /// (``GameSession/problemReportGame``), for a problem report; `nil`
    /// from the start screen.
    var game: String? = nil
    /// Decision 266, later: the lessons played on this device, for a
    /// problem report (``GameLauncher/lessonReport(in:)``).
    var lessons: String? = nil
    /// The game the settings were opened from, for its own settings
    /// (decision 154: holidays and other events); `nil` from the start
    /// screen.
    var session: GameSession? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var cityViewArea: CityViewArea?
    /// Decision 229: whether the game's own 3D map is open.
    @State private var showsMap3D = false
    /// Whether the game's website is open (decision 163), in Safari's view
    /// in the app.
    @State private var showsWebsite = false
    /// Decision 175: the secretary room's settings, on the device.
    @AppStorage(SecretarySettings.pauseKey) private var pausesForImportantEvents = true
    @AppStorage(SecretarySettings.nightSkipKey) private var skipsQuietNights = false
    @AppStorage(SecretarySettings.monthlyKey) private var monthlyReportMode = MonthlyReportMode.openAndPause.rawValue
    /// Whether the help guide is open (decision 177).
    @State private var showsHelp = false
    /// Decision 182: the map's time of day and weather, on the device.
    @AppStorage(MapAmbienceSettings.dayNightKey) private var showsDayNight = true
    @AppStorage(MapAmbienceSettings.weatherKey) private var showsWeather = true
    /// Decision 216: the lines' colours, on the device.
    @AppStorage(LinePalette.key) private var linePalette: LinePalette = .standard

    var body: some View {
        NavigationStack {
            List {
                soundSection
                mapSection
                lineColoursSection
                if let session {
                    eventsSection(session)
                    secretarySection(session.language)
                }
                if let session {
                    map3DSection(session)
                }
                previewSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .fullScreenCover(item: $cityViewArea) { area in
                CityView3D(area: area, close: { cityViewArea = nil })
            }
            .fullScreenCover(isPresented: $showsMap3D) {
                if let session {
                    Map3DPreviewScreen(session: session, close: { showsMap3D = false })
                }
            }
            .sheet(isPresented: $showsHelp) {
                HelpView(language: .app)
            }
            .sheet(isPresented: $showsWebsite) {
                if let url = URL(string: GameWebsite.home) {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
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

    /// The music and the sounds on or off, and under each its volumes
    /// (decision 219, stage 2): the music, the station chimes and the
    /// other effects. Kept on the device, for every game.
    private var soundSection: some View {
        let language = DisplayLanguage.app
        return Section {
            Toggle(isOn: Binding(get: { audio.musicOn }, set: { audio.setMusicOn($0) })) {
                Label("Music", systemImage: "music.note")
            }
            .accessibilityIdentifier("settings.music")
            volumeSlider(.music, title: language.text("Music Volume", "音樂音量"), systemImage: "music.note.list")
                .disabled(!audio.musicOn)
            Toggle(isOn: Binding(get: { audio.soundsOn }, set: { audio.setSoundsOn($0) })) {
                Label("Sound Effects", systemImage: "speaker.wave.2")
            }
            .accessibilityIdentifier("settings.sounds")
            volumeSlider(.chimes, title: language.text("Station Chimes", "車站鈴聲"), systemImage: "bell")
                .disabled(!audio.soundsOn)
            volumeSlider(.effects, title: language.text("Other Effects", "其他音效"), systemImage: "hammer")
                .disabled(!audio.soundsOn)
        } header: {
            Text("Sound")
        } footer: {
            Text(verbatim: language.text(
                "Station chimes ring when a train arrives. Other effects: building, changing tools, income and warnings. In silent mode the game makes no sound.",
                "車站鈴聲在列車到站時響。其他音效：建造、換工具、收入與警告。iPhone 在靜音模式時，遊戲不會發出聲音。"
            ))
        }
    }

    /// One of the three volumes, from silent to as loud as the game makes it.
    private func volumeSlider(_ category: SoundCategory, title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: systemImage)
            }
            Slider(
                value: Binding(get: { audio.volumes.level(of: category) }, set: { audio.setVolume($0, of: category) }),
                in: 0...1
            ) {
                Text(verbatim: title)
            } minimumValueLabel: {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("settings.volume.\(category.rawValue)")
        }
    }

    /// Decision 182: whether the map shows the time of day and the weather.
    private var mapSection: some View {
        Section {
            Toggle(isOn: $showsDayNight) {
                Label("Day and Night", systemImage: "moon.stars")
            }
            .accessibilityIdentifier("settings.dayNight")
            Toggle(isOn: $showsWeather) {
                Label("Weather Effects", systemImage: "cloud.rain")
            }
            .accessibilityIdentifier("settings.weather")
        } header: {
            Text("Map")
        } footer: {
            Text("Day and night: the map gets dark at night, and stations, trains and windows light up. Weather effects: rain and lightning on rainy and stormy days, and a typhoon sign at the stations a typhoon hits.")
        }
    }

    /// Decision 216: the colour-blind-safe palette for the lines.
    private var lineColoursSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { linePalette == .colourBlindSafe },
                set: { linePalette = $0 ? .colourBlindSafe : .standard }
            )) {
                Label("Colour-Blind Friendly Colours", systemImage: "eye")
            }
            .accessibilityIdentifier("settings.colourBlindLines")
        } header: {
            Text("Line Colours")
        } footer: {
            Text("Lines use colours that stay easy to tell apart with colour blindness, and every line badge shows its code.")
        }
    }

    /// Decision 154: how strongly the game's holidays (and later its other
    /// events) bite, kept in the game's save, and whose holidays they are.
    private func eventsSection(_ session: GameSession) -> some View {
        let language = session.language
        let current = session.world.disruptions?.level
        // Decision 154, later: a challenge's rules are fixed, so there the
        // menu shows what the game has and cannot be changed (an older save
        // with them on keeps them, and its result is not kept).
        let fixed = session.eventsAreFixed
        let levels: [DisruptionLevel?] = fixed ? [current] : [nil, .light, .standard]
        // Decision 258: the rules the game began with, which stay.
        let rules = NewGameRules(of: session.world)
        return Section {
            LabeledContent {
                Text(verbatim: language.text("\(rules.title(in: language)) rules", "\(rules.title(in: language))規則"))
            } label: {
                Label {
                    Text(verbatim: language.text("Rules", "規則"))
                } icon: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
            .accessibilityIdentifier("settings.rules")
            // Decision 184, later: a menu the ticks leave alone.
            TickStable(StableKey(current, levels, language)) {
                Picker(selection: Binding(get: { current }, set: { session.setDisruptionLevel($0) })) {
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
            }
            .disabled(fixed)
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
            if fixed, current != nil {
                Text(verbatim: GameSession.challengeSavedWithEventsText(in: language))
            } else if fixed {
                Text(verbatim: language.text(
                    "A challenge's rules are fixed and the same for every player: no holidays, weather, typhoons or fuel spells.",
                    "挑戰的規則固定，每位玩家都一樣：沒有連假、天氣、颱風與油電漲跌。"
                ))
            } else {
                Text(verbatim: language.text(
                    "Public holidays raise demand on every line, announced a week ahead. Rain lowers it, a typhoon (announced days ahead) cuts it at the stations in its path, and fuel spells change the day's energy cost. Light is half as strong as Standard. Applies to this game only.",
                    "國定假日時各線需求增加，一週前公布。下雨時需求減少，颱風（幾天前預警）讓路徑上的車站需求大減，油電價格偶爾漲跌、影響能源費。「輕」的影響是「標準」的一半。只套用在這一局。"
                ))
            }
        }
    }

    /// Decision 175: when the game stops by itself, and what happens when a
    /// month closes. Kept on the device, for every game.
    private func secretarySection(_ language: DisplayLanguage) -> some View {
        Section {
            Toggle(isOn: $pausesForImportantEvents) {
                Label {
                    Text(verbatim: language.text("Pause for important events", "重要事件自動暫停"))
                } icon: {
                    Image(systemName: "pause.circle")
                }
            }
            .accessibilityIdentifier("settings.autoPause")
            // Decision 305: the night's shortcut, pressed by itself.
            Toggle(isOn: $skipsQuietNights) {
                Label {
                    Text(verbatim: NightSkip.settingTitle(in: language))
                } icon: {
                    Image(systemName: "moon.zzz")
                }
            }
            .accessibilityIdentifier("settings.nightSkip")
            // Decision 184, later: a menu the ticks leave alone.
            TickStable(StableKey(monthlyReportMode, language)) {
                Picker(selection: $monthlyReportMode) {
                    ForEach(MonthlyReportMode.allCases, id: \.rawValue) { mode in
                        Text(verbatim: mode.title(in: language)).tag(mode.rawValue)
                    }
                } label: {
                    Label {
                        Text(verbatim: language.text("Monthly report", "每月報告"))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                }
                .accessibilityIdentifier("settings.monthlyReport")
            }
        } header: {
            Text(verbatim: language.text("Secretary", "秘書室"))
        } footer: {
            Text(verbatim: language.text(
                "The game pauses when a typhoon is announced, a goal is met, the cash goes below zero or a challenge has a week left. Every 30 days a monthly report compares the month with the one before; it is always kept in the news log.",
                "颱風預警、目標達成、現金轉為負債、挑戰剩不到 7 天時，遊戲會自動暫停。每 30 天有一張月報，和上個月比較；月報一定會記在新聞紀錄裡。"
            ) + language.text(" ", "") + NightSkip.settingFooter(in: language) + language.text(
                " Applies to every game on this device.", "套用到這台裝置上的每一局。"
            ))
        }
    }

    /// Decision 229, step 1: this game's railway and town in native 3D.
    private func map3DSection(_ session: GameSession) -> some View {
        let language = DisplayLanguage.app
        return Section {
            Button {
                showsMap3D = true
            } label: {
                Label {
                    Text(verbatim: language.text("3D Map of This Game", "這一局的 3D 地圖"))
                } icon: {
                    Image(systemName: "view.3d")
                }
            }
            .accessibilityIdentifier("settings.map3D")
        } footer: {
            Text(verbatim: language.text(
                "See your own railway, trains and town in 3D. Pinch closer and the map tilts. The number in the corner shows how smoothly it runs on this device.",
                "用 3D 看你自己的鐵路、列車與城鎮。兩指拉近，地圖就會傾斜。角落的數字是這台裝置跑起來的流暢度。"
            ))
        }
    }

    /// Decision 152: the 3D city view, a preview of what the game's 3D may
    /// look like (``CityView3D``); decision 161 adds Taichung Station, where
    /// the trains run on a viaduct.
    private var previewSection: some View {
        let language = DisplayLanguage.app
        return Section {
            Button {
                cityViewArea = .kaohsiung
            } label: {
                Label {
                    Text(verbatim: language.text("3D City: Kaohsiung Station", "3D 城市：高雄車站"))
                } icon: {
                    Image(systemName: "building.2")
                }
            }
            .accessibilityIdentifier("settings.cityView")
            Button {
                cityViewArea = .taichung
            } label: {
                Label {
                    Text(verbatim: language.text("3D City: Taichung Station", "3D 城市：臺中車站"))
                } icon: {
                    Image(systemName: "tram")
                }
            }
            .accessibilityIdentifier("settings.cityView.taichung")
        } header: {
            Text(verbatim: language.text("Preview", "搶先看"))
        } footer: {
            Text(verbatim: language.text(
                "A first look at a 3D city: the real buildings, roads and parks around Kaohsiung and Taichung Stations, with TRA trains on the viaduct at Taichung. It is a sample scene, not your own game, and needs the internet. Drag to move, pinch to zoom, two fingers to turn.",
                "搶先看 3D 城市：高雄車站與臺中車站周圍真實的建物、道路與公園，臺中的高架上有臺鐵列車在跑。這是示範畫面，不是你的這一局，需要網路連線。拖曳移動、兩指縮放、兩指旋轉。"
            ))
        }
    }

    /// Decision 127: the version testers quote, and a note to send about a
    /// problem, through the share sheet to wherever the player chooses.
    private var aboutSection: some View {
        let language = DisplayLanguage.app
        let report = ProblemReport.current(game: game, lessons: lessons)
        return Section {
            Button {
                showsHelp = true
            } label: {
                Label {
                    Text(verbatim: language.text("Help", "說明"))
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
            }
            .accessibilityIdentifier("settings.help")
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
            ProblemReportRows(game: game, session: session, lessons: lessons)
            Button {
                showsWebsite = true
            } label: {
                Label {
                    Text(verbatim: language.text("Website", "官網"))
                } icon: {
                    Image(systemName: "globe")
                }
            }
            .accessibilityIdentifier("settings.website")
        } header: {
            Text(verbatim: language.text("About", "關於"))
        } footer: {
            Text(verbatim: ProblemReportRows.footer(in: language) + language.text(
                " Website opens alongthelinegame.com in the game.",
                "「官網」在遊戲裡打開 alongthelinegame.com。"
            ))
        }
    }
}

/// Decision 127: a note about a problem, with the version, the device and,
/// from a game, what is in it, through the share sheet to wherever the
/// player chooses; decision 193: from a game, with its save and commands if
/// the player turns them on. The settings' About section and, from a game,
/// the game menu's own sheet (``ProblemReportSheet``) show the same rows.
struct ProblemReportRows: View {
    /// What is in the game (``GameSession/problemReportGame``); `nil` from
    /// the start screen.
    let game: String?
    let session: GameSession?
    /// Decision 266, later: the lessons' timings (``GameLauncher/lessonReport(in:)``).
    var lessons: String? = nil
    /// Decision 193: whether the game's save and commands go with a
    /// problem report: the player's choice, off until they turn it on.
    @State private var attachesCommandLog = false
    /// The file written for it, and what the player is told it holds;
    /// `nil` while it is being written.
    @State private var commandLog: (file: URL?, text: String)?

    /// What the rows do, under them.
    static func footer(in language: DisplayLanguage) -> String {
        language.text(
            "Report a Problem writes a note with the version, your device, how long each lesson took and, from a game, what is in it, for Mail, Messages or any app you choose. From a game you may also attach its save and what you did since, so the problem can be played again; you see what it holds before you send it. Nothing is sent until you send it. Testing in TestFlight? You can also take a screenshot and share it with the developer from there.",
            "「回報問題」會寫好一則附上版本、裝置、每一關花了多久（在遊戲中開啟時還有遊戲的狀態）的訊息，由你選擇用郵件、訊息或其他 App 傳送。在遊戲中也可以選擇附上這局的存檔和之後做過的事，讓問題可以重現；傳送前會列出裡面有什麼。你按下傳送前不會送出任何東西。用 TestFlight 測試時，也可以截圖後直接分享給開發者。"
        )
    }

    var body: some View {
        let language = DisplayLanguage.app
        let report = ProblemReport.current(game: game, lessons: lessons)
        if let session {
            Toggle(isOn: $attachesCommandLog) {
                Label {
                    Text(verbatim: language.text("Attach the Save and Commands", "附上存檔與指令紀錄"))
                } icon: {
                    Image(systemName: "paperclip")
                }
            }
            .accessibilityIdentifier("settings.report.attach")
            .onChange(of: attachesCommandLog) { _, attaches in
                commandLog = nil
                if attaches { prepareCommandLog(of: session, version: report.version, build: report.build) }
            }
            if attachesCommandLog {
                if let commandLog {
                    Text(verbatim: commandLog.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.report.attached")
                } else {
                    ProgressView()
                }
            }
        }
        Group {
            if attachesCommandLog, let file = commandLog?.file {
                ShareLink(item: file, subject: Text(verbatim: report.subject(in: language)), message: Text(verbatim: report.text(in: language))) {
                    reportLabel(language)
                }
            } else {
                ShareLink(item: report.text(in: language), subject: Text(verbatim: report.subject(in: language))) {
                    reportLabel(language)
                }
                .disabled(attachesCommandLog)
            }
        }
        .accessibilityIdentifier("settings.report")
    }

    private func reportLabel(_ language: DisplayLanguage) -> some View {
        Label {
            Text(verbatim: language.text("Report a Problem", "回報問題"))
        } icon: {
            Image(systemName: "exclamationmark.bubble")
        }
    }

    /// Writes the game's command log (decision 193) to a file for the share
    /// sheet, off the main actor: the save it starts from may be megabytes,
    /// and the digests read the bundled data files.
    private func prepareCommandLog(of session: GameSession, version: String, build: String) {
        let log = session.commandLog
        let world = session.world
        let language = DisplayLanguage.app
        Task {
            let prepared = await Task.detached(priority: .userInitiated) { () -> (file: URL?, text: String) in
                let data = CommandLogReport.digests { name in
                    let url = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: (name as NSString).pathExtension)
                    guard let url else { throw CocoaError(.fileNoSuchFile) }
                    return try Data(contentsOf: url)
                }
                let report = CommandLogReport(log: log, world: world, version: version, build: build, data: data)
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(CommandLogReport.fileName)
                do {
                    try report.encoded().write(to: file, options: .atomic)
                    return (file, report.attachmentText(in: language))
                } catch {
                    return (nil, language.text("The file could not be written: \(error.localizedDescription)", "無法寫出檔案：\(error.localizedDescription)"))
                }
            }.value
            if attachesCommandLog { commandLog = prepared }
        }
    }
}

extension ProblemReport {
    /// The note for this app, system and device, and the game it is
    /// written from.
    @MainActor static func current(game: String?, lessons: String? = nil) -> ProblemReport {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return ProblemReport(
            version: version, build: build, system: "\(device.systemName) \(device.systemVersion)", device: modelIdentifier, game: game,
            lessons: lessons
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

/// The problem report from the game menu (TestFlight 54.1: a player found
/// it only in the settings, and asked where to send a note): the same rows
/// as the settings' About section, on their own.
struct ProblemReportSheet: View {
    let game: String?
    let session: GameSession
    /// Decision 266, later: the lessons' timings.
    var lessons: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let language = DisplayLanguage.app
        NavigationStack {
            List {
                Section {
                    LabeledContent {
                        Text(verbatim: ProblemReport.current(game: game, lessons: lessons).versionText)
                            .textSelection(.enabled)
                    } label: {
                        Label {
                            Text(verbatim: language.text("Version", "版本"))
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                    }
                    ProblemReportRows(game: game, session: session, lessons: lessons)
                } footer: {
                    Text(verbatim: ProblemReportRows.footer(in: language))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text(verbatim: language.text("Report a Problem", "回報問題")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("report.done")
                }
            }
        }
    }
}

/// The keys of the map's time of day and weather (decision 182), shared by
/// the map and the settings: kept on the device with `@AppStorage`.
enum MapAmbienceSettings {
    static let dayNightKey = "map.showsDayNight"
    static let weatherKey = "map.showsWeather"
}
