import GamePresentation
import SwiftUI

/// Where the game's real-world data comes from and the licences it is used
/// under (``DataSourceCredits``), after the `Railway/` site's data sources
/// page: from the start screen, and from the map style menu of a real-world
/// map.
struct DataSourcesView: View {
    let language: DisplayLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(DataSourceCredits.sections(in: language)) { section in
                    Section {
                        ForEach(section.credits) { credit in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: credit.title)
                                    .font(.headline)
                                Text(verbatim: credit.detail)
                                    .font(.subheadline)
                                Text(verbatim: credit.notice)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                ForEach(credit.links, id: \.url) { link in
                                    if let url = URL(string: link.url) {
                                        // Borderless, so each link in the row
                                        // opens on its own.
                                        Link(destination: url) {
                                            Text(verbatim: link.title)
                                                .font(.footnote.weight(.semibold))
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(verbatim: section.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Data Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
