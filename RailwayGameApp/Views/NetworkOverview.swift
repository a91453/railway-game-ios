import GameCore
import GamePresentation
import SwiftUI

/// What has been built so far, read from the world: counts and every
/// station. Tapping a station selects it. Shown where there is room
/// (iPad, and the sidebar on wide screens).
struct NetworkOverview: View {
    let session: GameSession

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Network")
                    .font(.headline)
                Spacer(minLength: 8)
                Text(world.networkSummary(in: session.language))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)

            if world.stations.isEmpty {
                Text("No stations yet. Choose Network, then Platform, and tap the track to build one.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(world.stations) { station in
                        stationButton(station)
                    }
                }
            }
        }
    }

    private func stationButton(_ station: Station) -> some View {
        let isSelected = session.selectedStation?.id == station.id
        let place = station.placeText(in: session.language)
        return Button {
            session.selectStation(station.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tram.fill")
                    .foregroundStyle(isSelected ? Theme.onPrimary : Theme.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(station.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: place)
                        .font(.caption)
                        .monospacedDigit()
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: isSelected))
        .accessibilityLabel("\(station.name) station, \(place)")
        .accessibilityHint("Selects it on the map.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
