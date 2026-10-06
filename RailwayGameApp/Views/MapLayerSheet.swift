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

                Section {
                    Toggle(isOn: $layers.showsPopulationHeatmap) {
                        Label("Population Density Heatmap", systemImage: "person.3.sequence")
                    }
                    .accessibilityIdentifier("layer.populationHeatmap")
                } header: {
                    Text("Urban Demographics")
                } footer: {
                    Text("Population density grid overlay based on WorldPop 1km estimates (0 to 10,000+ people/km²).")
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
}
