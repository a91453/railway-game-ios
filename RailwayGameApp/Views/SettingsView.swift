import SwiftUI

/// The app's settings: the music and the sound effects on or off
/// (``GameAudio``), from the start screen and the game menu. Kept on the
/// device, never in a save.
struct SettingsView: View {
    let audio: GameAudio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { audio.musicOn }, set: { audio.setMusicOn($0) })) {
                        Label("Music", systemImage: "music.note")
                    }
                    .accessibilityIdentifier("settings.music")
                    Toggle(isOn: Binding(get: { audio.soundsOn }, set: { audio.setSoundsOn($0) })) {
                        Label("Sound Effects", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("settings.sounds")
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Sound effects: a chime when a train arrives, a rail joint when track is built and a whoosh when you change tools. In silent mode the game makes no sound.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings.done")
                }
            }
        }
    }
}
