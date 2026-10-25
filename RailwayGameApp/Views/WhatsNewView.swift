import GamePresentation
import SwiftUI

/// Decision 415: the "What's New" card (``WhatsNew``): the newest build's
/// news first, then the earlier builds'. The start screen shows it once
/// after an update; Help opens it again.
struct WhatsNewView: View {
    let language: DisplayLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(WhatsNew.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Section {
                            Text(verbatim: language.text("Before that", "更早的"))
                                .font(.headline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    lines(entry.items, heading: WhatsNew.itemsHeading(in: language), systemImage: "sparkles")
                    lines(entry.fixes, heading: WhatsNew.fixesHeading(in: language), systemImage: "wrench.and.screwdriver")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(WhatsNew.title(in: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Done", "完成"))
                    }
                    .accessibilityIdentifier(WhatsNew.doneIdentifier)
                }
            }
        }
        .accessibilityIdentifier("whatsNew.card")
    }

    @ViewBuilder private func lines(_ lines: [WhatsNew.Line], heading: String, systemImage: String) -> some View {
        if !lines.isEmpty {
            Section {
                ForEach(lines, id: \.english) { line in
                    Label {
                        Text(verbatim: line.text(in: language))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: systemImage)
                    }
                }
            } header: {
                Text(verbatim: heading)
            }
        }
    }
}
