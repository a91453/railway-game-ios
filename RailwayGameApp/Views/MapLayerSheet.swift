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
                    Text("Population: where people live, from WorldPop estimates on real-world maps and from your towns on blank maps. Travel demand: the trips starting in each area each hour. Demand change: how they rise or fall from the hour before.")
                }

                // Phase 6d: the city's layers, in the same group as the
                // three above (one layer at a time).
                Section {
                    Toggle(isOn: modeBinding(.landUse)) {
                        Label("Land Use", systemImage: "building.2")
                    }
                    .accessibilityIdentifier("layer.landUse")

                    Toggle(isOn: modeBinding(.landValue)) {
                        Label("Land Value", systemImage: "dollarsign.square")
                    }
                    .accessibilityIdentifier("layer.landValue")

                    Toggle(isOn: modeBinding(.coverage)) {
                        Label("Catchment Coverage", systemImage: "scope")
                    }
                    .accessibilityIdentifier("layer.catchmentCoverage")

                    // Decision 98: the zones the player drew.
                    Toggle(isOn: modeBinding(.zoning)) {
                        Label("Zoning", systemImage: "square.grid.3x3.fill")
                    }
                    .accessibilityIdentifier("layer.zoning")
                } header: {
                    Text("City")
                } footer: {
                    Text("Land use: homes, shops or offices, darker for taller buildings. Land value: dollars a square metre, higher near good train service; tap a cell for its parts. Catchment coverage: the land within 800 m of a station, and the people no station reaches.")
                }

                // Decision 124, H3: the ground's height and the steep
                // slopes, one layer at a time with those above.
                Section {
                    Toggle(isOn: modeBinding(.terrain)) {
                        Label("Height and Steep Slopes", systemImage: "mountain.2")
                    }
                    .accessibilityIdentifier("layer.terrain")
                } header: {
                    Text("Terrain")
                } footer: {
                    Text("The ground's height on real-world maps; hatching marks slopes steeper than 30%, where the city cannot build. Tap a cell for its height. Blank maps are flat.")
                }

                // Decision 178: the passengers on each stretch of track
                // against its trains' capacity, one layer at a time with
                // those above.
                Section {
                    Toggle(isOn: modeBinding(.sectionFlow)) {
                        Label("Passenger Load", systemImage: "chart.bar.xaxis")
                    }
                    .accessibilityIdentifier("layer.sectionFlow")
                } header: {
                    Text("Service")
                } footer: {
                    Text("Passenger load: the riders each stretch of track carries each way in the chosen hour, against what its trains can carry. A wider line has more riders, a darker blue a fuller train, and red is over capacity: add trains, run faster ones, or build a parallel line. Tap a stretch for the numbers.")
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
