import GameCore
import GamePresentation
import SwiftUI

/// Fleet overview and roster sheet displaying all trains in the network.
/// Each train's load uses the reference's train-panel load bar
/// (``TrainLoadBar``); the roster itself is the app's own (the `Ci/`
/// reference has no fleet list).
struct FleetOverviewSheet: View {
    @Bindable var session: GameSession
    @Environment(\.dismiss) private var dismiss
    /// The train a sale is being confirmed for (decision 180).
    @State private var sellingTrain: Train?
    /// Decision 179: how the roster is ordered.
    @State private var sort: FleetSort = .name

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryCard
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    if session.world.trains.isEmpty {
                        Text(verbatim: session.language.text("No trains in fleet yet. Purchase a train to begin operations.", "車隊中尚無列車。購買列車後即可開始營運。"))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(session.world.fleet(sortedBy: sort, in: session.language)) { train in
                            trainRow(train)
                        }
                    }
                } header: {
                    Text(verbatim: session.language.text("Trains (\(session.world.trains.count))", "列車清單（\(session.world.trains.count)）"))
                }
            }
            .navigationTitle(Text(verbatim: session.language.text("Fleet Overview", "車隊總覽")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Decision 179: in the bar, not a row of the list, so the
                // rows (and the UI tests that tap them) stay where they were.
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Picker(selection: $sort) {
                            ForEach(FleetSort.allCases, id: \.self) { order in
                                Text(verbatim: order.displayName(in: session.language)).tag(order)
                            }
                        } label: {
                            Text(verbatim: session.language.text("Sort by", "排序"))
                        }
                    } label: {
                        Label {
                            Text(verbatim: session.language.text("Sort", "排序"))
                        } icon: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                    .accessibilityIdentifier("fleet.sort")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: session.language.text("Done", "完成"))
                    }
                    .accessibilityIdentifier("fleet.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            Text(verbatim: sellingTrain.map {
                session.language.text("Sell \($0.name)?", "出售 \($0.name)？")
            } ?? ""),
            isPresented: Binding(get: { sellingTrain != nil }, set: { if !$0 { sellingTrain = nil } }),
            titleVisibility: .visible,
            presenting: sellingTrain
        ) { train in
            Button(role: .destructive) {
                session.sellTrain(train.id)
            } label: {
                Text(verbatim: session.language.text(
                    "Sell for \(session.world.trainSaleQuote(train.id).moneyText)",
                    "以 \(session.world.trainSaleQuote(train.id).moneyText) 出售"
                ))
            }
        } message: { train in
            Text(verbatim: session.language.text(
                "Brings 70 % of what is left of its cost on the books.",
                "可取回帳面價值的 70 %。"
            ))
        }
    }

    private var summaryCard: some View {
        let trains = session.world.trains
        let placedCount = trains.filter { $0.position != nil }.count
        // Trains on the track only: one in the depot is not in service.
        let fleetLoad = session.world.fleetLoadInfo()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.language.text("Fleet Size", "車隊規模"))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(verbatim: "\(trains.count) \(session.language.text("trains", "列"))")
                        .font(.headline.weight(.bold).monospacedDigit())
                }

                Divider()
                    .frame(height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.language.text("In Service", "運轉中"))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(verbatim: "\(placedCount) \(session.language.text("trains", "列"))")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.primary)
                }

                Divider()
                    .frame(height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.language.text("Avg Load", "平均滿載率"))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(verbatim: fleetLoad.map { "\($0.percentage)%" } ?? "--")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(fleetLoad?.isOverload == true ? Theme.error : Theme.textPrimary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func trainRow(_ train: Train) -> some View {
        let isSelected = session.selectedTrainID == train.id
        let isFollowing = session.isFollowing(train.id)
        let language = session.language

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "train.side.front.car")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Theme.primary : Theme.textSecondary)

                Text(verbatim: train.name)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()

                Text(verbatim: train.carsText(in: language))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                if train.position != nil {
                    Button {
                        if isFollowing {
                            session.stopFollowingTrain()
                        } else {
                            session.selectTrain(train.id)
                            session.followTrain(train.id)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isFollowing ? "location.fill" : "location")
                                .font(.caption2.weight(.bold))
                            Text(verbatim: isFollowing ? language.text("Following", "跟隨中") : language.text("Follow", "跟隨"))
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isFollowing ? Theme.primary.opacity(0.14) : Theme.chip)
                        .foregroundStyle(isFollowing ? Theme.primary : Theme.textPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fleet.follow.\(train.name)")
                }
            }

            if train.position != nil {
                HStack(spacing: 6) {
                    if let service = session.world.trainServiceStatus(of: train.id, in: language) {
                        if let name = service.serviceName {
                            Text(verbatim: name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.primary)
                        }
                        Text(verbatim: service.stopText)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)

                        if let punctuality = service.punctuality {
                            Text(verbatim: punctuality.text(in: language))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(punctuality == .onTime ? Theme.success : Theme.warning)
                        }
                    } else if let stop = session.world.stationStopText(of: train.id, in: language) {
                        Text(verbatim: stop)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(verbatim: session.world.trainPathStatusText(of: train.id, in: language))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if let load = session.world.trainLoadInfo(of: train.id) {
                    TrainLoadBar(load: load, language: language)
                }
            } else {
                HStack {
                    Text(verbatim: language.text("In depot / off track", "未上軌（車庫待命中）"))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    // Decision 180: a train on no line and off the track is sold
                    // back at 70 % of its books.
                    if session.world.canSellTrain(train.id) {
                        Button {
                            sellingTrain = train
                        } label: {
                            Text(verbatim: language.text(
                                "Sell \(session.world.trainSaleQuote(train.id).moneyText)",
                                "出售 \(session.world.trainSaleQuote(train.id).moneyText)"
                            ))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.chip)
                            .foregroundStyle(Theme.textPrimary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("fleet.sell.\(train.name)")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            session.selectTrain(train.id)
            dismiss()
        }
    }
}
