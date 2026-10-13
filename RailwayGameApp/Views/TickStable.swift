import SwiftUI

/// A part of a game screen drawn again only when `key` changes, not on every
/// tick: for a native menu (`Menu`, a `Picker` shown as a menu) that has to
/// stay as it is while it is open.
///
/// The game loop replaces the session's world every 100 ms, and every view
/// that reads it is drawn again. A native menu drawn again while it is open
/// is rebuilt: it scrolls back to its top, cross-fades its rows (two layers
/// of text) and can drop a tap (TestFlight 54.1, decision 184, later). This
/// is the same remedy as the equatable menus of #449 (``MapCanvas``'s), for
/// menus with no view of their own.
///
/// `key` holds everything the content shows. The content is built from
/// values worked out before it, never from `session.world`: a part that reads
/// the world is drawn again every tick whatever its key, and one that reads
/// a value not in its key would show it out of date. Its actions may call
/// the session.
struct TickStable<Key: Equatable & Sendable, Content: View>: View {
    private let key: Key
    private let content: () -> Content

    init(_ key: Key, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        self.content = content
    }

    var body: some View {
        Drawn(key: key, content: content)
            .equatable()
    }

    private struct Drawn: View, Equatable {
        let key: Key
        let content: () -> Content

        nonisolated static func == (lhs: Drawn, rhs: Drawn) -> Bool {
            lhs.key == rhs.key
        }

        var body: some View {
            content()
        }
    }
}

/// Several values as the key of a ``TickStable`` part.
struct StableKey<each Value: Equatable & Sendable>: Equatable, Sendable {
    private let values: (repeat each Value)

    init(_ values: repeat each Value) {
        self.values = (repeat each values)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in repeat (each lhs.values, each rhs.values) {
            if left != right { return false }
        }
        return true
    }
}
