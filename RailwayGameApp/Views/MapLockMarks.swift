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
                    .frame(width: 0, height: 0, alignment: .center)
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
                .contentShape(Circle())
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: lock.isUnlocked
            ? session.language.text("Land you can buy", "可以買的土地")
            : session.language.text("Locked land", "還沒解鎖的土地")))
        .accessibilityHint(Text(verbatim: session.language.text("Shows its price", "看看價格")))
        .accessibilityIdentifier("map.lock.\(lock.tile.row).\(lock.tile.column)")
    }
}
