import GameCore

/// What the station panel offers about a road to a station (decision 400
/// B.3): derived from ``GameWorld/stationRoadQuote(at:)`` only.
public struct StationRoadOffer: Hashable, Sendable {
    /// The button's words, or the line the panel shows when there is
    /// nothing to build.
    public let text: String
    /// What the road costs, when it can be built.
    public let quote: StationRoadQuote?

    public var canBuild: Bool { quote != nil }
}

extension GameWorld {
    /// The station panel's line about a road to station `id`: "Build Station
    /// Road · 256 m · $12,800" when the roads reach within 512 m, why not
    /// when they do not, and `nil` for a world without roads, a station that
    /// does not exist or one a road reaches already.
    public func stationRoadOffer(of id: StationID, in language: DisplayLanguage) -> StationRoadOffer? {
        do throws(GameError) {
            let quote = try stationRoadQuote(at: id)
            let metres = Money(quote.metres).displayText, price = quote.price.moneyText
            return StationRoadOffer(
                text: language.text("Build Station Road · \(metres) m · \(price)", "鋪站前路 · \(metres) 公尺 · \(price)"), quote: quote
            )
        } catch {
            switch error {
            case .roadsNotEnabled, .unknownStation, .stationOnRoad: return nil
            default: return StationRoadOffer(text: error.playerMessage(in: language), quote: nil)
            }
        }
    }
}

extension GameSession {
    /// Builds a road from the selected station to the nearest road and pays
    /// for it (decision 400 B.3).
    public func buildStationRoadAtSelectedStation() {
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station on the map first.", "請先在地圖上選擇車站。"))
            return
        }
        let quote = try? world.stationRoadQuote(at: station.id)
        perform(.buildStationRoad(station.id)) { _, _, _ in
            let price = quote?.price.moneyText ?? Money.zero.moneyText
            return language.text("A road now reaches \(station.name), for \(price).", "\(station.name) 的站前路鋪好了，花費 \(price)。")
        }
    }
}
