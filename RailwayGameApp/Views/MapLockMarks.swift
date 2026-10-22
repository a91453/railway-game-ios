import GameCore
import GamePresentation
import SwiftUI

/// The locks on the tiles of the map not bought yet (ARCHITECTURE decision
/// 167, later): one on each tile for sale, shut until the best day unlocks
/// it, open after; a tap opens that tile's card, as choosing it after the
/// Expand button would. Which tiles, where and what a tap does are
/// GamePresentation's (``GameSession/mapLocks(on:viewport:clearOf:)``).
struct MapLockMarks: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets

    var body: some View {
        let clear = ScreenInsets(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing)
        ZStack(alignment: .topLeading) {
            ForEach(session.mapLocks(on: camera, viewport: viewport, clearOf: clear)) { lock in
                mark(lock)
                    .fixedSize()
                    .position(x: lock.at.x, y: lock.at.y)
            }
        }
        // Not on this view, which covers the whole map: hidden from
        // VoiceOver it would hide the map from UI tests' taps.
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
    }

    private func mark(_ lock: MapLock) -> some View {
        let size: Double = 34
        return Button {
            session.openMapLock(lock.tile)
        } label: {
            (lock.isUnlocked ? MapGlyph.lockOpen : MapGlyph.lock).image
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.55, height: size * 0.55)
                .foregroundStyle(lock.isUnlocked ? Theme.onAccent : Theme.primary)
                .frame(width: size, height: size)
                .background(lock.isUnlocked ? Theme.accent : Theme.panel, in: Circle())
                .overlay(Circle().strokeBorder(lock.isUnlocked ? Theme.onAccent : Theme.primary, lineWidth: 2))
                .frame(minWidth: 44, minHeight: 44)
                // The whole finger's square, not the circle: on an iPad a
                // tap on the circle's middle row (y ± 0.3 of its centre, the
                // whole width) fell through to the map, and a tap 2 points
                // off it opened the card (only_testing run 39826506139).
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: lock.isUnlocked
            ? session.language.text("Land you can buy", "可以買的土地")
            : session.language.text("Locked land", "還沒解鎖的土地")))
        .accessibilityHint(Text(verbatim: session.language.text("Shows its price", "看看價格")))
        .accessibilityIdentifier("map.lock.\(lock.tile.row).\(lock.tile.column)")
    }
}
