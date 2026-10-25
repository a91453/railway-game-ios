import GameCore
import GamePresentation
import SwiftUI
import UniformTypeIdentifiers

// Decision 409: a network shared between players with no server: the
// game's own save type, the file shared, and the sheet that offers a file
// someone sent.

extension UTType {
    /// The game's own save type, declared in the app's Info.plist; the
    /// file is JSON.
    static let alongTheLineSave = UTType(exportedAs: SharedNetwork.typeIdentifier, conformingTo: .json)
}

/// The game as a save file to share (Stage C4, the reference's "导出本地存档"),
/// written when the player shares it, from the game as it is then: the menu
/// that offers it does not build the world to save every tick.
///
/// Decision 409: of the game's own type, so a friend who gets it taps it
/// open in the game, with the name the player wrote on the postcard.
struct ExportedSave: Transferable {
    let session: GameSession

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .alongTheLineSave) { save in
            let (world, news) = await (save.session.worldToSave, save.session.news)
            let company = UserDefaults.standard.string(forKey: PostcardSheet.companyNameKey)
            return SentTransferredFile(try SaveLibrary.exportFile(for: world, news: news, company: company, at: Date()))
        }
    }
}

/// A network a friend sent (decision 409): its postcard, and what to do
/// with it, a new game of the player's own or a look round. Putting it
/// away opens nothing.
struct ReceivedNetworkSheet: View {
    let network: SharedNetwork
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss
    @Environment(\.regionStyle) private var region
    @State private var map: PostcardMap?
    @State private var skyline: CitySkyline?

    private var language: DisplayLanguage { launcher.language }

    var body: some View {
        NavigationStack {
            let postcard = network.postcard(in: language)
            ScrollView {
                VStack(spacing: 16) {
                    GeometryReader { proxy in
                        let scale = min(1, proxy.size.width / PostcardLayout.size.width)
                        PostcardCard(postcard: postcard, world: network.world, map: map, skyline: skyline)
                            .environment(\.regionStyle, region)
                            .scaleEffect(scale, anchor: .top)
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }
                    .aspectRatio(PostcardLayout.size.width / PostcardLayout.size.height, contentMode: .fit)
                    .frame(maxWidth: PostcardLayout.size.width)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: ([postcard.title, postcard.subtitle] + postcard.figures.map { "\($0.value) \($0.label)" }).joined(separator: ", ")))
                    .accessibilityIdentifier("sharedNetwork.postcard")

                    ForEach(SharedNetworkChoice.allCases, id: \.self) { choice in
                        VStack(alignment: .leading, spacing: 6) {
                            if choice == .newGame {
                                Button {
                                    open(as: choice)
                                } label: {
                                    Text(verbatim: choice.title(in: language))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(ThemeProminentButtonStyle())
                                .accessibilityIdentifier(choice.accessibilityIdentifier)
                            } else {
                                Button {
                                    open(as: choice)
                                } label: {
                                    Text(verbatim: choice.title(in: language))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.primary)
                                .controlSize(.large)
                                .accessibilityIdentifier(choice.accessibilityIdentifier)
                            }
                            Text(verbatim: choice.detail(in: language))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle(language.text("A Network for You", "朋友傳來的路網"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Cancel", "取消")) { dismiss() }
                        .accessibilityIdentifier("sharedNetwork.cancel")
                }
            }
            .task {
                // As the postcard sheet draws it (decision 215).
                let world = network.world
                if world.geoAnchor == nil, !world.land.isEmpty {
                    skyline = await Task.detached(priority: .userInitiated) { CitySkyline(world: world) }.value
                }
                let water = launcher.water
                map = await Task.detached(priority: .userInitiated) { PostcardMap(world: world, water: water) }.value
            }
        }
    }

    private func open(as choice: SharedNetworkChoice) {
        launcher.open(network, as: choice)
        dismiss()
    }
}

/// Shows the network a friend sent (``ReceivedNetworkSheet``) over the
/// start screen or the game, and a spinner while its file is read.
struct ReceivesSharedNetworks: ViewModifier {
    let launcher: GameLauncher

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                guard url.isFileURL else { return }
                Task {
                    await launcher.receiveNetwork(at: url).value
                    ReceivedFile.removeCopy(at: url)
                }
            }
            .sheet(isPresented: Binding(
                get: { launcher.receivedNetwork != nil },
                set: { if !$0 { launcher.dismissReceivedNetwork() } }
            )) {
                if let network = launcher.receivedNetwork {
                    ReceivedNetworkSheet(network: network, launcher: launcher)
                }
            }
            .overlay {
                if launcher.isReadingReceivedNetwork {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(Text(verbatim: launcher.language.text("Opening the network", "正在打開路網")))
                }
            }
    }
}

/// A file another app handed the game: iOS copies it into the app's
/// `Documents/Inbox` (the Info.plist does not open documents in place).
enum ReceivedFile {
    /// Deletes the copy at `url` once it is read, when it is the game's
    /// own copy in its inbox; a file elsewhere is left alone.
    static func removeCopy(at url: URL) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(inbox + "/") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
