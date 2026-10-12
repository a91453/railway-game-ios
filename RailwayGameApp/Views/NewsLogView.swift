import GameCore
import GamePresentation
import SwiftUI

/// The news log (decision 175): what the station master said and what
/// happened, the newest first, each with its game date; an item that is
/// about a station, a line or a train has a Go button that moves the map
/// there. Opened by the HUD's bell or by tapping the station master's
/// bubble. Everything is read from the session's log.
struct NewsLogView: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    /// How many items were new when the log opened: the first of the list.
    @State private var newCount: Int

    init(session: GameSession) {
        self.session = session
        _newCount = State(initialValue: session.news.unread)
    }

    var body: some View {
        let language = session.language
        NavigationStack {
            Group {
                if session.news.items.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text(verbatim: language.text("No news yet", "還沒有消息"))
                        } icon: {
                            Image(systemName: "bell")
                        }
                    } description: {
                        Text(verbatim: language.text(
                            "The station master's reminders, goals met, holidays and typhoons are kept here.",
                            "站長的提醒、達成的目標、連假與颱風都會記在這裡。"
                        ))
                    }
                } else {
                    List {
                        ForEach(Array(session.news.items.enumerated()), id: \.element.id) { index, item in
                            row(item, isNew: index < newCount, language: language)
                        }
                    }
                    .listStyle(.plain)
                    .accessibilityIdentifier("news.list")
                }
            }
            .navigationTitle(Text(verbatim: language.text("News", "新聞紀錄")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Done", "完成"))
                    }
                    .accessibilityIdentifier("news.done")
                }
            }
        }
        .onAppear { session.markNewsRead() }
        .onDisappear { session.markNewsRead() }
    }

    private func row(_ item: NewsItem, isNew: Bool, language: DisplayLanguage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.category.symbolName)
                .font(.subheadline)
                .foregroundStyle(item.category.isWorry ? Theme.warning : Theme.primary)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.text(in: language))
                    .font(.subheadline.weight(isNew ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: item.date.text(in: language))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            if session.canGo(to: item) {
                Button {
                    session.goTo(item)
                    dismiss()
                } label: {
                    Text(verbatim: language.text("Go", "前往"))
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("news.go")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
