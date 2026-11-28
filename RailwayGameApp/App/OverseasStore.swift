import Foundation
import GamePresentation
import Security
import StoreKit
import SwiftUI

/// Decision 1010: the App Store's side of the overseas maps unlock
/// (``OverseasUnlock``), StoreKit 2. It asks the App Store whether this
/// Apple Account owns the unlock (`Transaction.currentEntitlements`, which
/// counts a purchase restored or shared by the family) and which build the
/// player first downloaded (`AppTransaction`), sells it, restores it, and
/// hands the answer to the launcher, which closes the overseas maps'
/// new games without it.
///
/// The last answer is kept on the device, so the maps do not close for a
/// moment at every launch or when the App Store cannot be reached; the
/// purchase's is replaced by every later answer (a refund closes them
/// again), the gift's, once given, is kept.
@MainActor
@Observable
final class OverseasStore {
    static let shared = OverseasStore()

    /// What the device knows of the unlock.
    private(set) var state: OverseasUnlock.State
    /// Whether a purchase or a restore is under way.
    private(set) var isWorking = false
    /// What the last purchase or restore came to, until it is read.
    var outcome: OverseasUnlock.Outcome?

    @ObservationIgnored private var product: Product?
    @ObservationIgnored private var updates: Task<Void, Never>?
    /// Counts the readings of the entitlement, so only the latest counts.
    @ObservationIgnored private var entitlementReading = 0
    @ObservationIgnored private weak var launcher: GameLauncher?
    /// A Debug build without the launch argument to lock the maps: every
    /// map open, as the UI tests and the screenshots need.
    private var opensWithoutStore = false
    @ObservationIgnored private let defaults: UserDefaults

    static let purchasedKey = "overseasUnlock.purchased"
    static let giftKey = "overseasUnlock.freeVersionPlayer"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = OverseasUnlock.State(
            purchased: defaults.bool(forKey: Self.purchasedKey), freeVersionPlayer: defaults.bool(forKey: Self.giftKey)
        )
    }

    /// Hands the launcher the device's last answer at once, then asks the
    /// App Store and listens for purchases made elsewhere (another device,
    /// Ask to Buy approved, a refund).
    func start(launcher: GameLauncher, opensWithoutStore: Bool = false) {
        self.launcher = launcher
        self.opensWithoutStore = opensWithoutStore
        publish()
        guard !opensWithoutStore, updates == nil else { return }
        // Decision 1010: the free map outlives a reinstall in the Keychain
        // (and reaches the player's other devices with iCloud Keychain).
        if let kept = FreeMapKeychain.read() { launcher.adoptFreeMap(kept) }
        if let chosen = launcher.freeMap, FreeMapKeychain.read() == nil { FreeMapKeychain.write(chosen) }
        launcher.onFreeMapChosen = { FreeMapKeychain.write($0) }
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update, transaction.productID == OverseasUnlock.productID {
                    await transaction.finish()
                }
                await self.readEntitlement()
            }
        }
        refresh()
    }

    /// Asks the App Store again: at the start and each time the app comes
    /// back to the front (a first answer missed offline comes then).
    func refresh() {
        guard !opensWithoutStore, launcher != nil else { return }
        Task { [weak self] in
            await self?.readEntitlement()
            await self?.readGift()
            await self?.loadProduct()
        }
    }

    /// Buys the unlock with SwiftUI's purchase action (the view's
    /// `@Environment(\.purchase)`, which shows the App Store's sheet over
    /// the right window).
    func buy(with purchase: PurchaseAction) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if product == nil { await loadProduct() }
        guard let product else {
            outcome = .failed
            return
        }
        do {
            switch try await purchase(product) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    outcome = .failed
                    return
                }
                await transaction.finish()
                // Ahead of any reading still under way (``readEntitlement()``).
                entitlementReading += 1
                setPurchased(transaction.revocationDate == nil)
                outcome = .bought
            case .pending:
                outcome = .pending
            case .userCancelled:
                outcome = .cancelled
            @unknown default:
                outcome = .failed
            }
        } catch {
            outcome = .failed
        }
    }

    /// Restore Purchases: asks the App Store for this Apple Account's
    /// purchases again (it may ask the player to sign in).
    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch {
            if case StoreKitError.userCancelled = error { return }
            outcome = .failed
            return
        }
        await readEntitlement()
        // Asked of the App Store afresh, not the device's copy: the player
        // pressed it, so a sign-in may come up.
        await readGift(refreshing: true)
        outcome = state.isOpen ? .restored : .nothingToRestore
    }

    // MARK: - The App Store's answers

    /// Whether this Apple Account owns the unlock now. Only the latest
    /// answer counts: a reading that began before a purchase finished
    /// does not write its older answer over it.
    private func readEntitlement() async {
        entitlementReading += 1
        let reading = entitlementReading
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == OverseasUnlock.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        guard reading == entitlementReading else { return }
        setPurchased(owned)
    }

    /// Whether the player first downloaded a free version. Asked until the
    /// answer is yes; no answer (offline, not verified) changes nothing.
    private func readGift(refreshing: Bool = false) async {
        guard !state.freeVersionPlayer else { return }
        let result: VerificationResult<AppTransaction>
        do {
            result = refreshing ? try await AppTransaction.refresh() : try await AppTransaction.shared
        } catch {
            return
        }
        guard case .verified(let app) = result else { return }
        let environment: OverseasUnlock.StoreEnvironment =
            app.environment == .production ? .production : app.environment == .xcode ? .xcode : .sandbox
        guard OverseasUnlock.isFreeVersionPlayer(originalVersion: app.originalAppVersion, environment: environment) else { return }
        state.freeVersionPlayer = true
        defaults.set(true, forKey: Self.giftKey)
        publish()
    }

    /// The product and its price in the player's country.
    private func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [OverseasUnlock.productID]).first
        state.price = product?.displayPrice
        publish()
    }

    private func setPurchased(_ purchased: Bool) {
        state.purchased = purchased
        defaults.set(purchased, forKey: Self.purchasedKey)
        publish()
    }

    /// What the game goes by: ``state``, or every map open in a Debug
    /// build that asks no App Store.
    var shownState: OverseasUnlock.State {
        opensWithoutStore ? .open : state
    }

    /// Hands the launcher what is known now: nothing in a Debug build that
    /// asks no App Store, so nothing is sold and the maps open as decision
    /// 712 opens them.
    private func publish() {
        launcher?.overseasUnlock = opensWithoutStore ? nil : state
    }
}

/// Decision 1010: the free map kept in the Keychain, which a reinstall
/// does not clear, synchronizable so iCloud Keychain carries it to the
/// player's other devices. One generic password item; nothing secret.
enum FreeMapKeychain {
    private static let service = "overseasUnlock.freeMap"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: service,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
    }

    static func read() -> String? {
        var asked = query
        asked[kSecReturnData as String] = true
        asked[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(asked as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ id: String) {
        let data = Data(id.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var added = query
        added[kSecValueData as String] = data
        added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(added as CFDictionary, nil)
    }
}

/// Decision 1010: the unlock's row, in the map picker while it is for sale
/// and in the settings: which map is free, its name, what it opens, Buy
/// with the price and Restore Purchases; once open, why it is.
struct OverseasUnlockRow: View {
    let store: OverseasStore
    let language: DisplayLanguage
    /// The free map's line (``OverseasUnlock/freeMapText(_:in:)``), shown
    /// while the unlock is for sale.
    var freeMap: String?
    @Environment(\.purchase) private var purchase

    var body: some View {
        let state = store.shownState
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: state.isOpen ? "checkmark.seal.fill" : "map.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
                Text(verbatim: OverseasUnlock.title(in: language))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            if !state.isOpen, let freeMap {
                Text(verbatim: freeMap)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("overseasUnlock.freeMap")
            }
            Text(verbatim: state.isOpen ? OverseasUnlock.openText(state, in: language) : OverseasUnlock.summary(in: language))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !state.isOpen {
                HStack(spacing: 12) {
                    Button {
                        Task { await store.buy(with: purchase) }
                    } label: {
                        Text(verbatim: OverseasUnlock.buyTitle(price: state.price, in: language))
                            .frame(minHeight: 44)
                    }
                    // Styled buttons, so a List row's two buttons are
                    // pressed one at a time, not both by a tap on the row.
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("overseasUnlock.buy")
                    Button {
                        Task { await store.restore() }
                    } label: {
                        Text(verbatim: OverseasUnlock.restoreTitle(in: language))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("overseasUnlock.restore")
                    if store.isWorking {
                        ProgressView()
                    }
                }
                .disabled(store.isWorking)
            }
            if let text = store.outcome?.text(in: language) {
                Text(verbatim: text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("overseasUnlock.outcome")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overseasUnlock")
        // The line of the last purchase or restore goes with the screen.
        .onDisappear { store.outcome = nil }
    }
}
