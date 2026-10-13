import GameCore

// What the goals panel's "City requests" section and the station master
// show of the city's requests (ARCHITECTURE decision 183), and the
// session's commands to take one on or turn it down, in English or
// Traditional Chinese (see ``DisplayLanguage``). All of it is read from the
// world; nothing here is kept.

/// A request as the goals panel lists it.
public struct CityRequestRow: Identifiable, Hashable, Sendable {
    public let id: Int
    public let kind: CityRequestKind
    /// "Open a station at Banqiao", "Raise Central's riders"…
    public let title: String
    /// What meeting it takes, and what it pays.
    public let detail: String
    public let reward: Money
    public let rewardText: String
    /// Whether it is in hand (else an offer).
    public let isActive: Bool
    /// How far it has come, 0 to 1000 thousandths, and in words ("6 / 10
    /// calls"); an offer's is what it would start from.
    public let progress: Int64
    public let progressText: String
    /// The days left: to meet it, or for an offer to take it on.
    public let daysLeft: Int64
    public let daysLeftText: String
    /// Where "Show on map" goes, or `nil` for the whole network.
    public let location: PlanPoint?
}

/// A request that ended, for the panel's record.
public struct CityRequestResultRow: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let succeeded: Bool
    public let text: String
}

extension GameWorld {
    /// Whether this game has the city's requests, so that the section is shown.
    public var hasCityRequests: Bool {
        cityRequests != nil
    }

    /// The requests in hand, then the offers, by ID.
    public func cityRequestRows(in language: DisplayLanguage, placeNames: PlaceNames? = nil) -> [CityRequestRow] {
        guard let requests = cityRequests else { return [] }
        let today = clock.now.seconds / GameTime.secondsPerDay
        let monthEnd = (today / CityRequests.monthDays + 1) * CityRequests.monthDays
        return (requests.active + requests.offers).map { request in
            let active = request.acceptedDay != nil
            let current = active ? request.progress : measure(request)
            let progress = request.target > 0 ? min(1_000, max(0, current) * 1_000 / request.target) : 0
            let days = active ? max(0, (request.deadline ?? today) - today + 1) : max(0, monthEnd - today)
            let daysText = active
                ? language.text("\(days) day\(days == 1 ? "" : "s") left", "剩 \(days) 天")
                : language.text("Open for \(days) more day\(days == 1 ? "" : "s")", "還能承接 \(days) 天")
            return CityRequestRow(
                id: request.id, kind: request.kind, title: title(of: request, in: language, placeNames: placeNames),
                detail: detail(of: request, in: language), reward: request.reward, rewardText: request.reward.moneyText,
                isActive: active, progress: progress, progressText: progressText(of: request, current: current, in: language),
                daysLeft: days, daysLeftText: daysText, location: location(of: request)
            )
        }
    }

    /// The requests that ended, the latest first.
    public func cityRequestResults(in language: DisplayLanguage, placeNames: PlaceNames? = nil) -> [CityRequestResultRow] {
        guard let requests = cityRequests else { return [] }
        return requests.results.reversed().map { result in
            let title = title(of: result.request, in: language, placeNames: placeNames)
            let text = result.succeeded
                ? language.text("Met on day \(result.day + 1): \(result.request.reward.moneyText)", "第 \(result.day + 1) 天達成：\(result.request.reward.moneyText)")
                : language.text("Not met by day \(result.day + 1)", "第 \(result.day + 1) 天未達成")
            return CityRequestResultRow(id: result.request.id, title: title, succeeded: result.succeeded, text: text)
        }
    }

    /// "Trust ★★☆☆☆ · 1 of 2 in hand".
    public func cityTrustText(in language: DisplayLanguage) -> String? {
        guard let requests = cityRequests else { return nil }
        let stars = String(repeating: "★", count: requests.trust) + String(repeating: "☆", count: CityRequests.maximumTrust - requests.trust)
        return language.text(
            "City's trust \(stars) · \(requests.active.count) of \(requests.capacity) in hand",
            "城市信賴度 \(stars) · 進行中 \(requests.active.count) / \(requests.capacity) 件"
        )
    }

    /// "Subsidies so far $1,200,000 (due on the 1st: $300,000)".
    public func citySubsidyText(in language: DisplayLanguage) -> String? {
        guard let requests = cityRequests else { return nil }
        guard requests.owed > .zero else {
            return language.text("Subsidies so far \(requests.paid.moneyText)", "累計補助 \(requests.paid.moneyText)")
        }
        return language.text(
            "Subsidies so far \(requests.paid.moneyText) (due on the 1st: \(requests.owed.moneyText))",
            "累計補助 \(requests.paid.moneyText)（下月 1 日入帳 \(requests.owed.moneyText)）"
        )
    }

    /// The section's help text.
    public func cityRequestsHelp(in language: DisplayLanguage) -> String {
        language.text(
            "On the first of every month the city asks for up to three things. Take one on and meet it in time: the subsidy is paid on the first of the next month and the city trusts you a star more. Missing one costs a star, never money. Two stars of trust let you hold two at once, four stars three.",
            "每月 1 日城市會提出最多三件委託。承接後在期限內達成，補助金在下個月 1 日入帳，信賴度加一星；逾期只扣一星，不罰錢。信賴度兩星可同時承接兩件，四星三件。"
        )
    }

    // MARK: - Words

    /// A place's name: a real map's settlement, village or township near
    /// it, else its direction and distance from the nearest station.
    func placeText(_ point: PlanPoint, in language: DisplayLanguage, placeNames: PlaceNames?) -> String {
        if let placeNames, let frame = RealWorldFrame(world: self) {
            let coordinate = frame.coordinate(worldX: Double(point.x), worldY: Double(point.y))
            let here = RealRailways.Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let place = placeNames.nearby(here).first ?? placeNames.township(containing: here) {
                return place.name(in: language)
            }
        }
        let nearest = stations.min { a, b in
            let da = (a.point.x - point.x) * (a.point.x - point.x) + (a.point.y - point.y) * (a.point.y - point.y)
            let db = (b.point.x - point.x) * (b.point.x - point.x) + (b.point.y - point.y) * (b.point.y - point.y)
            return (da, a.id) < (db, b.id)
        }
        guard let nearest else { return language.text("a town on the map", "地圖上的城鎮") }
        let direction = UnservedCluster(center: point, people: 0).direction(from: nearest.point)
        let km = "\(direction.tenthsOfKm / 10).\(direction.tenthsOfKm % 10)"
        return language.text(
            "the town \(km) km \(direction.compass.title(in: language)) of \(nearest.name)",
            "\(nearest.name)\(direction.compass.title(in: language))方 \(km) 公里的聚落"
        )
    }

    private func stationText(_ id: StationID?, in language: DisplayLanguage) -> String {
        id.flatMap { station(id: $0)?.name } ?? language.text("a station gone", "已拆除的車站")
    }

    func title(of request: CityRequest, in language: DisplayLanguage, placeNames: PlaceNames?) -> String {
        switch request.kind {
        case .newStation:
            let place = request.point.map { placeText($0, in: language, placeNames: placeNames) } ?? ""
            return language.text("A station for \(place)", "為\(place)設站通車")
        case .stationRiders:
            // A name that already ends in 站 ("…車站") does not take another.
            let station = stationText(request.station, in: language)
            return language.text("More riders at \(station)", station.hasSuffix("站") ? "\(station)運量提升" : "\(station)站運量提升")
        case .networkRiders:
            return language.text("A record day for the railway", "全網旅客創新高")
        case .materials:
            return language.text("Building materials for \(stationText(request.station, in: language))", "建材運到\(stationText(request.station, in: language))")
        case .population:
            return language.text("Grow the town round \(stationText(request.station, in: language))", "\(stationText(request.station, in: language))周邊人口成長")
        case .tourism:
            let sight = request.attraction.flatMap(attraction(id:))
            let name = sight?.name(in: language) ?? language.text("a sight", "景點")
            return language.text("Tourists for \(name)", "\(name)觀光客")
        }
    }

    func detail(of request: CityRequest, in language: DisplayLanguage) -> String {
        let days = request.days
        switch request.kind {
        case .newStation:
            return language.text(
                "\(request.baseline) people live and work there with no station. Within \(days) days, have a station within 800 m called at \(request.target) times a day.",
                "這裡有 \(request.baseline) 人居住與工作，卻沒有車站。\(days) 天內在 800 公尺內設站，每天至少 \(request.target) 班停靠。"
            )
        case .stationRiders:
            return language.text(
                "From \(request.baseline) to \(request.target) planned trips a day within \(days) days.",
                "\(days) 天內每日計畫旅次從 \(request.baseline) 提升到 \(request.target)。"
            )
        case .networkRiders:
            return language.text(
                "Your best day carried \(request.baseline). Carry \(request.target) paying passengers in one day within \(days) days.",
                "歷史最佳單日 \(request.baseline) 人次。\(days) 天內單日載客達 \(request.target) 人次。"
            )
        case .materials:
            return language.text(
                "The town is short of materials. Bring \(request.target) t there by freight train within \(days) days.",
                "這裡缺建材。\(days) 天內用貨運列車送 \(request.target) 噸到這站。"
            )
        case .population:
            return language.text(
                "From \(request.baseline) to \(request.target) residents within 800 m within \(days) days.",
                "\(days) 天內 800 公尺內的居民從 \(request.baseline) 人成長到 \(request.target) 人。"
            )
        case .tourism:
            return language.text(
                "\(request.target) tourists to the sight within \(days) days.",
                "\(days) 天內累計 \(request.target) 名觀光客到訪。"
            )
        }
    }

    private func progressText(of request: CityRequest, current: Int64, in language: DisplayLanguage) -> String {
        switch request.kind {
        case .newStation: language.text("\(current) / \(request.target) calls a day", "每天 \(current) / \(request.target) 班")
        case .stationRiders: language.text("\(current) / \(request.target) trips a day", "每日 \(current) / \(request.target) 旅次")
        case .networkRiders: language.text("best \(current) / \(request.target)", "最佳 \(current) / \(request.target) 人次")
        case .materials: language.text("\(current) / \(request.target) t", "\(current) / \(request.target) 噸")
        case .population: language.text("\(current) / \(request.target) residents", "\(current) / \(request.target) 人")
        case .tourism: language.text("\(current) / \(request.target) tourists", "\(current) / \(request.target) 人")
        }
    }
}

extension GameSession {
    /// Takes on the city's request `id`.
    public func acceptRequest(_ id: Int) {
        guard let request = world.cityRequest(id: id) else { return }
        let title = world.title(of: request, in: language, placeNames: placeNames)
        perform(.acceptRequest(id)) { _, _, _ in
            language.text("Request taken on: \(title).", "已承接委託：\(title)。")
        }
    }

    /// Turns down the city's offer `id`, or gives up request `id` in hand.
    public func declineRequest(_ id: Int) {
        guard let request = world.cityRequest(id: id) else { return }
        let title = world.title(of: request, in: language, placeNames: placeNames)
        let active = request.acceptedDay != nil
        perform(.declineRequest(id)) { _, _, _ in
            active
                ? language.text("Request given up: \(title). The city trusts you a star less.", "已放棄委託：\(title)。城市信賴度減一星。")
                : language.text("Request turned down: \(title).", "已婉拒委託：\(title)。")
        }
    }
}
