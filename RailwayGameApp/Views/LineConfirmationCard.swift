import GameCore
import GamePresentation
import SwiftUI

/// Decision 303: the card a new line's ✓ raises before anything is bought.
/// Its name and colour, its length, time and stops, its first and last
/// train, and the trains at each time of day with how often they come;
/// what is still to buy and what it costs. Everything starts at what the
/// ✓ opened before (one train all day), so Confirm alone opens the line
/// as it did. The settings and the figures are the session's
/// (``GameSession/lineConfirmation``, ``GameSession/lineConfirmationPreview``);
/// this view only draws them.
struct LineConfirmationCard: View {
    let session: GameSession
    /// Called after Confirm opened the line.
    var opened: () -> Void = {}

    var body: some View {
        let language = session.language
        NavigationStack {
            Form {
                if let card = session.lineConfirmation {
                    let preview = session.lineConfirmationPreview
                    nameSection(card, preview: preview, in: language)
                    hoursSection(card, preview: preview, in: language)
                    if let preview {
                        trainsSection(preview, in: language)
                    }
                    purchaseSection(preview, in: language)
                }
            }
            .navigationTitle(Text(verbatim: language.text("New line", "新路線")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        session.cancelLineConfirmation()
                    } label: {
                        Text(verbatim: language.text("Back", "返回"))
                    }
                    .accessibilityIdentifier("line.confirm.back")
                }
            }
        }
    }

    // MARK: - Sections

    private func nameSection(_ card: LineConfirmation, preview: LineConfirmationPreview?, in language: DisplayLanguage) -> some View {
        Section {
            TextField(
                language.text("Line name", "路線名稱"),
                text: Binding(
                    get: { session.lineConfirmation?.name ?? "" },
                    set: { name in session.updateLineConfirmation { var card = $0; card.name = name; return card } }
                )
            )
            .accessibilityIdentifier("line.confirm.name")
            colorRow(card, in: language)
            if let preview {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: preview.figures)
                        .monospacedDigit()
                    Text(verbatim: preview.direction)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("line.confirm.figures")
            }
        }
    }

    /// The colour-blind-friendly colours (#567), and Automatic first.
    private func colorRow(_ card: LineConfirmation, in language: DisplayLanguage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                swatch(nil, chosen: card.color == nil, in: language)
                ForEach(LineConfirmation.colors, id: \.self) { color in
                    swatch(color, chosen: card.color == color, in: language)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("line.confirm.colors")
    }

    private func swatch(_ color: LineColor?, chosen: Bool, in language: DisplayLanguage) -> some View {
        Button {
            session.updateLineConfirmation { var card = $0; card.color = color; return card }
        } label: {
            ZStack {
                Circle()
                    .fill(color.map(Palette.color) ?? Theme.textSecondary.opacity(0.25))
                if color == nil {
                    Text(verbatim: language.text("A", "自"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                if chosen {
                    Circle()
                        .strokeBorder(Theme.textPrimary, lineWidth: 3)
                }
            }
            .frame(width: 32, height: 32)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(verbatim: color.map(\.hexText) ?? language.text("Automatic colour", "自動顏色")))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func hoursSection(_ card: LineConfirmation, preview: LineConfirmationPreview?, in language: DisplayLanguage) -> some View {
        Section {
            clockRow(
                title: language.text("First train", "首班車"),
                time: preview?.firstTrain ?? "",
                id: "line.confirm.first",
                move: { minutes in session.updateLineConfirmation { $0.movingOpen(by: minutes) } }
            )
            clockRow(
                title: language.text("Last train", "末班車"),
                time: preview?.lastTrain ?? "",
                id: "line.confirm.last",
                move: { minutes in session.updateLineConfirmation { $0.movingClose(by: minutes) } }
            )
        } header: {
            Text(verbatim: language.text("Hours", "營運時間"))
        }
    }

    /// One clock time, 10 minutes back or on with the stepper.
    private func clockRow(title: String, time: String, id: String, move: @escaping (Int) -> Void) -> some View {
        Stepper(
            onIncrement: { move(LineConfirmation.minuteStep) },
            onDecrement: { move(-LineConfirmation.minuteStep) }
        ) {
            HStack {
                Text(verbatim: title)
                Spacer()
                Text(verbatim: time)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityIdentifier(id)
    }

    private func trainsSection(_ preview: LineConfirmationPreview, in language: DisplayLanguage) -> some View {
        Section {
            ForEach(preview.rows, id: \.period) { row in
                Stepper(
                    onIncrement: { session.updateLineConfirmation { $0.setting(row.period.level, to: row.trains + 1) } },
                    onDecrement: { session.updateLineConfirmation { $0.setting(row.period.level, to: row.trains - 1) } }
                ) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(verbatim: row.period.title(in: language))
                            Spacer()
                            Text(verbatim: language.text(row.trains == 1 ? "1 train" : "\(row.trains) trains", "\(row.trains) 列"))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        Text(verbatim: row.hours + " · " + row.headwayText(in: language))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier("line.confirm.trains.\(row.period.rawValue)")
            }
        } header: {
            Text(verbatim: language.text("Trains", "列車"))
        } footer: {
            if let limit = preview.trackLimit {
                Text(verbatim: limit)
                    .accessibilityIdentifier("line.confirm.limit")
            } else {
                Text(verbatim: language.text(
                    "The morning and evening peaks run the same trains.",
                    "早晚尖峰跑一樣多的列車。"
                ))
            }
        }
    }

    private func purchaseSection(_ preview: LineConfirmationPreview?, in language: DisplayLanguage) -> some View {
        Section {
            if let preview {
                Text(verbatim: preview.purchaseText(in: language))
                    .font(.subheadline.monospacedDigit())
                    .accessibilityIdentifier("line.confirm.purchase")
                if let shortfall = preview.shortfall {
                    Text(verbatim: shortfall)
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .accessibilityIdentifier("line.confirm.shortfall")
                }
            } else {
                Text(verbatim: language.text(
                    "This line can't run as set. Go back and change the stops or the track.",
                    "這條路線照這樣開不了。請返回改停靠站或軌道。"
                ))
                .font(.footnote)
                .foregroundStyle(Theme.warning)
            }
            Button {
                session.confirmLine()
                if session.lineConfirmation == nil { opened() }
            } label: {
                Text(verbatim: language.text("Open Line", "開通路線"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            // Decision 110: the card's main action, as the theme draws one.
            .buttonStyle(ThemeProminentButtonStyle())
            .disabled(preview == nil || preview?.shortfall != nil)
            .accessibilityIdentifier("line.confirm.done")
        }
    }
}
