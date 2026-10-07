import GamePresentation
import SwiftUI

/// Where the game's real-world data comes from and the licences it is used
/// under (``DataSourceCredits``), after the `Railway/` site's data sources
/// page: from the start screen, and from the map style menu of a real-world
/// map.
struct DataSourcesView: View {
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss

    private var language: DisplayLanguage { launcher.language }

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
                                    .foregroundStyle(Theme.textSecondary)
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
                // The bundled data files that could not be read: shown so a
                // broken file is seen rather than silently missing.
                let issues = launcher.realWorldIssues + (launcher.railways?.operations?.timetableIssues ?? [])
                if launcher.isLoadingRealWorldData {
                    Section {
                        ProgressView {
                            Text(verbatim: language.text("Reading the real-world data…", "正在讀取實景資料…"))
                                .font(.footnote)
                        }
                    }
                } else if !issues.isEmpty {
                    Section {
                        ForEach(issues, id: \.self) { issue in
                            Text(verbatim: issue.description)
                                .font(.footnote.monospaced())
                        }
                    } header: {
                        Text(verbatim: language.text("Files that could not be read", "無法讀取的檔案"))
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
