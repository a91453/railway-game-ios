import GameCore
import GamePresentation
import SwiftUI

/// The new game's options (decision 177), after A-Train's difficulty choice:
/// the rules, simple or realistic (decision 256);
/// easy, standard or expert, with the cash each starts with; how much the
/// holidays and weather disturb the traffic; whether building materials,
/// the towns beyond the map's edge and buying the map are on; a real-world
/// map's ground, real or flat (decision 198); the funds, standard or
/// unlimited (decision 200); and the map's
/// seed, to share a map. The choices are kept on the device
/// (``GameLauncher/newGameOptions``) and used by every new game until
/// changed; a line at the bottom says what they change.
struct NewGameOptionsView: View {
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss
    @State private var seedText = ""

    private var language: DisplayLanguage { launcher.language }

    private var options: Binding<NewGameOptions> {
        Binding(get: { launcher.newGameOptions }, set: { launcher.newGameOptions = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: difficulty) {
                        ForEach(NewGameOptions.Difficulty.allCases, id: \.self) { level in
                            Text(verbatim: level.title(in: language)).tag(level)
                        }
                    } label: {
                        Text(verbatim: language.text("Difficulty", "難度"))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("newGameOptions.difficulty")
                    LabeledContent(
                        language.text("Starting cash", "起始資金"),
                        value: launcher.newGameOptions.funds == .unlimited ? "∞" : launcher.newGameOptions.startingBalance.moneyText
                    )
                } header: {
                    Text(verbatim: language.text("Difficulty", "難度"))
                }
                // Decision 256: simple rules unless chosen realistic.
                Section {
                    Picker(selection: options.rules) {
                        ForEach(NewGameRules.allCases, id: \.self) { rules in
                            Text(verbatim: rules.title(in: language)).tag(rules)
                        }
                    } label: {
                        Text(verbatim: language.text("Rules", "規則"))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("newGameOptions.rules")
                } header: {
                    Text(verbatim: language.text("Rules", "規則"))
                } footer: {
                    Text(verbatim: launcher.newGameOptions.rules.explanation(in: language)
                        + " " + language.text("A game keeps its rules to the end.", "開始後不能更改。"))
                }
                // Decision 200: a managed game that pays for nothing.
                Section {
                    Picker(selection: options.funds) {
                        ForEach(NewGameOptions.Funds.allCases, id: \.self) { funds in
                            Text(verbatim: funds.title(in: language)).tag(funds)
                        }
                    } label: {
                        Text(verbatim: language.text("Funds", "資金"))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("newGameOptions.funds")
                } header: {
                    Text(verbatim: language.text("Funds", "資金"))
                } footer: {
                    Text(verbatim: language.text(
                        "Unlimited: building and buying cost nothing, and fares, costs, passengers and towns follow the usual rules. Games with unlimited funds do not count for achievements.",
                        "無限：建造與購買都不扣款，票收、成本、乘客與城鎮照一般規則。資金無限的局不計成就。"
                    ))
                }
                Section {
                    Picker(selection: disruption) {
                        ForEach(NewGameOptions.Disruption.allCases, id: \.self) { level in
                            Text(verbatim: level.title(in: language)).tag(level)
                        }
                    } label: {
                        Text(verbatim: language.text("Holidays, weather and typhoons", "假日、天氣與颱風"))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("newGameOptions.disruption")
                } header: {
                    Text(verbatim: language.text("Disruptions", "干擾事件"))
                } footer: {
                    Text(verbatim: language.text(
                        "How strongly public holidays, weather, typhoons and fuel prices change the number of passengers. The difficulty chooses this unless you do.",
                        "國定假日、天氣、颱風與油價對旅客數的影響強度。除非自己選擇，否則由難度決定。"
                    ))
                }
                Section {
                    // Decision 256: simple rules have none.
                    Toggle(language.text("Building materials", "建材供應"), isOn: toggle(\.buildingMaterials))
                        .disabled(launcher.newGameOptions.rules == .simple)
                    Toggle(language.text("Outside connections", "外部連接"), isOn: toggle(\.outsideConnections))
                    Toggle(language.text("Buy the map tile by tile", "分區購買地圖"), isOn: toggle(\.buysMap))
                } header: {
                    Text(verbatim: language.text("More rules", "其他規則"))
                } footer: {
                    Text(verbatim: language.text(
                        "Materials (realistic rules only): towns need them to grow. Outside connections: riders arrive from beyond the map's edge. Buying the map applies to a blank map; real-world maps decide for themselves.",
                        "建材（只有寫實規則）：城市要有建材才能成長。外部連接：地圖邊緣外的旅客會進來。分區購買只適用於空白地圖，實景地圖有自己的規則。"
                    ))
                }
                Section {
                    // Decision 198: real-world maps only; a blank map is flat.
                    Picker(selection: options.ground) {
                        ForEach(NewGameOptions.Ground.allCases, id: \.self) { ground in
                            Text(verbatim: ground.title(in: language)).tag(ground)
                        }
                    } label: {
                        Text(verbatim: language.text("Terrain", "地形"))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("newGameOptions.ground")
                } header: {
                    Text(verbatim: language.text("Terrain (real-world maps)", "地形（實景地圖）"))
                } footer: {
                    Text(verbatim: language.text(
                        "Real: track rises and falls with the hills, with tunnels and viaducts where they are steep. Flat: track is always level, with no grades or tunnels to think about. Blank maps are always flat.",
                        "真實：軌道隨山勢起伏，太陡的地方要用隧道或高架。平坦：軌道一律水平，不用考慮坡度與隧道。空白地圖一律平坦。"
                    ))
                }
                Section {
                    TextField(language.text("Random each game", "每局隨機"), text: $seedText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("newGameOptions.seed")
                        .onChange(of: seedText) { _, text in
                            let seed = text.isEmpty ? nil : NewGameOptions.seed(from: text)
                            if launcher.newGameOptions.seed != seed { launcher.newGameOptions.seed = seed }
                        }
                    Button(language.text("Pick a seed", "挑一個種子")) {
                        seedText = String(UInt32.random(in: .min ... .max))
                    }
                    if !seedText.isEmpty {
                        Button(language.text("Random each game", "每局隨機"), role: .destructive) {
                            seedText = ""
                        }
                    }
                } header: {
                    Text(verbatim: language.text("Map seed", "地圖種子"))
                } footer: {
                    Text(verbatim: language.text(
                        "The same seed draws the same towns and events, so a map can be shared. Digits only, up to 10 of them.",
                        "相同的種子會產生相同的城鎮與事件，可以和朋友分享地圖。只能輸入數字，最多 10 位。"
                    ))
                }
                Section {
                    Text(verbatim: launcher.newGameOptions.summary(in: language))
                        .font(.footnote)
                        .accessibilityIdentifier("newGameOptions.summary")
                    Button {
                        dismiss()
                        launcher.startNewGame()
                    } label: {
                        Text(verbatim: language.text("Start New Game", "開始新遊戲"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("newGameOptions.start")
                } header: {
                    Text(verbatim: language.text("What this changes", "這些設定的效果"))
                }
            }
            .navigationTitle(language.text("New Game Options", "新遊戲選項"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Done", "完成")) { dismiss() }
                        .accessibilityIdentifier("newGameOptions.done")
                }
            }
            .onAppear {
                seedText = launcher.newGameOptions.seed.map(String.init) ?? ""
            }
        }
    }

    /// Changing the difficulty also drops a disruption level chosen apart,
    /// so the new difficulty is what the player sees.
    private var difficulty: Binding<NewGameOptions.Difficulty> {
        Binding(
            get: { launcher.newGameOptions.difficulty },
            set: {
                launcher.newGameOptions.difficulty = $0
                launcher.newGameOptions.disruptionChoice = nil
            }
        )
    }

    private var disruption: Binding<NewGameOptions.Disruption> {
        Binding(
            get: { launcher.newGameOptions.disruption },
            set: {
                let followsDifficulty = $0 == launcher.newGameOptions.difficulty.disruption
                launcher.newGameOptions.disruptionChoice = followsDifficulty ? nil : $0
            }
        )
    }

    private func toggle(_ keyPath: WritableKeyPath<NewGameOptions, Bool>) -> Binding<Bool> {
        Binding(get: { launcher.newGameOptions[keyPath: keyPath] }, set: { launcher.newGameOptions[keyPath: keyPath] = $0 })
    }
}
