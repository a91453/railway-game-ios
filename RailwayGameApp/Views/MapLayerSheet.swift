import GamePresentation
import SwiftUI

/// Sheet controlling map overlay visibility and display options.
struct MapLayerSheet: View {
    @Binding var layers: MapLayerPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $layers.showsStationNames) {
                        Label("Station Names", systemImage: "character.textbox")
                    }
                    .accessibilityIdentifier("layer.stationNames")

                    Toggle(isOn: $layers.showsWaitingCounts) {
                        Label("Waiting Passenger Counts", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("layer.waitingCounts")

                    Toggle(isOn: $layers.showsCatchmentRings) {
                        Label("800m Catchment Area", systemImage: "circle.circle")
                    }
                    .accessibilityIdentifier("layer.catchmentRings")
                } header: {
                    Text("Station Overlays")
                } footer: {
                    Text("Station catchment area shows the 800-metre walking reference area (~10 minutes walk).")
                }

                // The reference's "population and travel data" column of its
                // map layer panel: one of the three layers at a time.
                Section {
                    Toggle(isOn: $layers.showsPopulationHeatmap) {
                        Label("Population Density Heatmap", systemImage: "person.3.sequence")
                    }
                    .accessibilityIdentifier("layer.populationHeatmap")

                    Toggle(isOn: modeBinding(.travel)) {
                        Label("Travel Demand", systemImage: "figure.walk.motion")
                    }
                    .accessibilityIdentifier("layer.travelDemand")

                    Toggle(isOn: modeBinding(.movement)) {
                        Label("Demand Change", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("layer.demandChange")
                } header: {
                    Text("Population and Travel Data")
                } footer: {
                    Text("Population: WorldPop 1 km estimates on real-world maps (0 to 10,000+ people a cell), the towns' 64 m cells on blank maps (people per square km). Travel demand: the trips starting in each 1 km square in each hour, from the stations' demand. Demand change: how they rise or fall from the hour before.")
                }
            }
            .navigationTitle("Map Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("layer.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Layer `mode` on or off (`togglePopTravelLayerFromMapPanel`).
    private func modeBinding(_ mode: PopTravelMode) -> Binding<Bool> {
        Binding(
            get: { layers.shows(mode) },
            set: { layers.setShows(mode, $0) }
        )
    }
}
