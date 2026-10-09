import GameCore
import GamePresentation
import SwiftUI

extension EnvironmentValues {
    /// Whether the details card is open (decision 119): the station's tag
    /// stands over the map only while it is not.
    @Entry var mapDetailsOpen = false
}

/// The tag by the station selected while looking at the map (decision
/// 119), under it: its name, who waits there and its lines' colours (``StationTag``).
/// A tap on it opens the details card; its pencil, as holding the station
/// does, opens the station's panel, so VoiceOver and Switch Control have a
/// way to it that is not a long press. Shown only while neither is open.
struct MapStationTagView: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets
    @Environment(\.mapDetailsOpen) private var detailsOpen
    @Environment(GameScreenState.self) private var screen
    @State private var size = CGSize(width: 160, height: 44)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let tag {
                content(tag)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .offset(placement(under: camera.screenPoint(of: tag.location)))
                    .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        .animation(.spring(duration: 0.25, bounce: 0.3), value: tag?.station)
    }

    private var tag: StationTag? {
        guard session.tool == .select, session.tutorial == nil, !detailsOpen, screen.panel == nil,
              let id = session.selectedStationID
        else { return nil }
        return StationTag(world: session.world, station: id)
    }

    private func content(_ tag: StationTag) -> some View {
        HStack(spacing: 0) {
            Button {
                screen.detailsRequests &+= 1
            } label: {
                HStack(spacing: 8) {
                    if !tag.lines.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(tag.lines.prefix(4), id: \.id) { line in
                                Capsule()
                                    .fill(Palette.lineColor(line.id, custom: line.color))
                                    .frame(width: 5, height: 18)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: tag.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if let waiting = tag.waitingText(in: session.language) {
                            Text(verbatim: waiting)
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: [tag.name, tag.waitingText(in: session.language)].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityHint(Text(verbatim: session.language.text("Shows the station's details.", "顯示車站的詳細資料。")))
            .accessibilityIdentifier("map.stationTag")
            Divider()
                .frame(height: 24)
            Button {
                screen.panel = .station
            } label: {
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: session.language.text("Edit the station", "編輯車站")))
            .accessibilityIdentifier("map.stationTag.edit")
        }
        .fixedSize()
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    /// Under `point`, clear of the station's mark (its bubbles, decision
    /// 109, stand over it) and of its name under the mark (decision 123:
    /// the tag covered the name's lower half), or over it when there is no
    /// room below; kept clear of the controls along the map's edges.
    private func placement(under point: ScreenPoint) -> CGSize {
        let margin = 8.0, clearance = 34.0
        let width = Double(size.width), height = Double(size.height)
        let minX = Double(insets.leading) + margin
        let maxX = viewport.width - Double(insets.trailing) - width - margin
        let x = min(max(point.x - width / 2, minX), max(minX, maxX))
        let top = Double(insets.top) + margin
        let bottom = viewport.height - Double(insets.bottom) - margin
        var y = point.y + clearance
        if y + height > bottom {
            y = point.y - clearance - height
        }
        y = min(max(y, top), max(top, bottom - height))
        return CGSize(width: x, height: y)
    }
}
