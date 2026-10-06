import GameCore
import GamePresentation
import SwiftUI

/// Fleet overview and roster sheet displaying all trains in the network.
///
/// Faithfully reproduces the `Ci/` reference's `#panel-train` roster list
/// and `Railway/` reference's fleet status table.
struct FleetOverviewSheet: View {
    @Bindable var session: GameSession
    @Environment(\.dismiss) private var dismiss

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
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.world.trains) { train in
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
    }

    private var summaryCard: some View {
        let trains = session.world.trains
        let placedCount = trains.filter { $0.position != nil }.count
        let totalRiders = trains.reduce(Int64(0)) { sum, train in
            sum + session.world.riders(of: train.id).reduce(0) { $0 + $1.count }
        }
        let totalCapacity = trains.reduce(Int64(0)) { sum, train in
            sum + train.ratedCapacity
        }
        let fleetLoadPercent = totalCapacity > 0 ? Int((200 * totalRiders + totalCapacity) / (2 * totalCapacity)) : 0
        let fleetLoadFactor = totalCapacity > 0 ? Double(totalRiders) / Double(totalCapacity) : 0.0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.language.text("Fleet Size", "車隊規模"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(trains.count) \(session.language.text("trains", "列"))")
                        .font(.headline.weight(.bold).monospacedDigit())
                }

                Divider()
                    .frame(height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.language.text("In Service", "運轉中"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(placedCount) \(session.language.text("trains", "列"))")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Palette.metroBlue)
                }

                Divider()
                    .frame(height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.language.text("Avg Load", "平均滿載率"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(fleetLoadPercent)%")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(fleetLoadFactor >= 0.90 ? Color.red : (fleetLoadFactor >= 0.70 ? Palette.metroAmber : Color.green))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func trainRow(_ train: Train) -> some View {
        let isSelected = session.selectedTrainID == train.id
        let isFollowing = isSelected && session.isFollowingTrain
        let language = session.language

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "train.side.front.car")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Palette.metroBlue : .secondary)

                Text(verbatim: train.name)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()

                Text(verbatim: train.carsText(in: language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if train.position != nil {
                    Button {
                        if isFollowing {
                            session.setFollowingTrain(false)
                        } else {
                            session.selectTrain(train.id, following: true)
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
                        .background(isFollowing ? Palette.metroBlue.opacity(0.18) : Palette.chipBackground)
                        .foregroundStyle(isFollowing ? Palette.metroBlue : .primary)
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
                                .foregroundStyle(Palette.metroBlue)
                        }
                        Text(verbatim: service.stopText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let punctuality = service.punctuality {
                            Text(verbatim: punctuality.text(in: language))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(punctuality == .onTime ? Color.green : Color.orange)
                        }
                    } else if let stop = session.world.stationStopText(of: train.id, in: language) {
                        Text(verbatim: stop)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: train.pathText(in: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let load = session.world.trainLoadInfo(of: train.id) {
                    TrainLoadBar(load: load, language: language)
                }
            } else {
                Text(verbatim: language.text("In depot / off track", "未上軌（車庫待命中）"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
