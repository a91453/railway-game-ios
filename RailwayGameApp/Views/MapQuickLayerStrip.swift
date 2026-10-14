import GamePresentation
import SwiftUI

/// The layers used most, one tap each, under the status pill (ARCHITECTURE
/// decision 224, option 5B, `docs/art/railway-ui-redesign-2026-10-14/s5-*.png`):
/// station names, waiting counts, passenger load and population, each an
/// icon over its name, navy when on, and More, which opens the full layer
/// list. The same settings as the list (``StoredMapLayerSheet``), so each
/// shows what the other changed.
struct MapQuickLayerStrip: View {
    let language: DisplayLanguage
    let openList: () -> Void
    @AppStorage("mapShowsStationNames") private var showsStationNames = true
    @AppStorage("mapShowsWaitingCounts") private var showsWaitingCounts = true
    @AppStorage("mapShowsCatchmentRings") private var showsCatchmentRings = true
    @AppStorage("mapPopTravelMode") private var popTravelModeName = ""

    private var layers: MapLayerPreferences {
        MapLayerPreferences(
            showsStationNames: showsStationNames,
            showsWaitingCounts: showsWaitingCounts,
            showsCatchmentRings: showsCatchmentRings,
            popTravelMode: PopTravelMode(rawValue: popTravelModeName)
        )
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MapQuickLayer.allCases, id: \.self) { layer in
                let isOn = layer.isOn(in: layers)
                Button {
                    store(layer.toggled(layers))
                } label: {
                    cell(symbol: layer.symbolName, title: layer.title(in: language), isOn: isOn)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: layer.title(in: language)))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("map.quickLayer.\(layer)")
            }
            Rectangle()
                .fill(Theme.panelBorder)
                .frame(width: 1, height: 26)
                .padding(.horizontal, 2)
            Button(action: openList) {
                cell(symbol: "square.3.layers.3d", title: language.text("More", "更多"), isOn: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: language.text("All map layers", "全部地圖圖層")))
            .accessibilityIdentifier("map.quickLayer.more")
        }
        .padding(3)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.ink, lineWidth: 1.5)
        )
    }

    /// An icon over its name: navy with the panel's colour when on, the
    /// secondary text colour when off, so the state shows without colour
    /// too.
    private func cell(symbol: String, title: String, isOn: Bool) -> some View {
        VStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(height: 18)
            Text(verbatim: title)
                .font(.system(size: 9.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isOn ? Theme.panel : Theme.textSecondary)
        .frame(width: 46, height: 44)
        .background(isOn ? Theme.textPrimary : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    private func store(_ layers: MapLayerPreferences) {
        showsStationNames = layers.showsStationNames
        showsWaitingCounts = layers.showsWaitingCounts
        showsCatchmentRings = layers.showsCatchmentRings
        popTravelModeName = layers.popTravelMode?.rawValue ?? ""
    }
}
