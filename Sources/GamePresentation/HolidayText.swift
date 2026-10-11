import GameCore

// Public holidays in words (ARCHITECTURE decision 154): their names, the
// lines the station panel lists while one is announced or running, and the
// review the station master gives the day after one ends.

extension DisruptionLevel {
    /// The level's name in the settings.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .light: language.text("Light", "輕")
        case .standard: language.text("Standard", "標準")
        }
    }
}

/// The name of a country whose holidays the game keeps, for the settings.
public func holidayCountryName(_ code: String, in language: DisplayLanguage) -> String {
    let names: [String: (String, String)] = [
        "AE": ("United Arab Emirates", "阿拉伯聯合大公國"), "AU": ("Australia", "澳洲"), "BR": ("Brazil", "巴西"), "CA": ("Canada", "加拿大"),
        "CN": ("China", "中國"), "DE": ("Germany", "德國"), "FR": ("France", "法國"), "GB": ("United Kingdom", "英國"),
        "HK": ("Hong Kong", "香港"), "ID": ("Indonesia", "印尼"), "IN": ("India", "印度"), "JP": ("Japan", "日本"),
        "KR": ("South Korea", "南韓"), "MX": ("Mexico", "墨西哥"), "NL": ("Netherlands", "荷蘭"), "NZ": ("New Zealand", "紐西蘭"),
        "PL": ("Poland", "波蘭"), "SA": ("Saudi Arabia", "沙烏地阿拉伯"), "SG": ("Singapore", "新加坡"), "TH": ("Thailand", "泰國"),
        "TW": ("Taiwan", "台灣"), "US": ("United States", "美國"), "VN": ("Vietnam", "越南"), "ZA": ("South Africa", "南非"),
    ]
    guard let name = names[code] else { return code }
    return language.text(name.0, name.1)
}

extension HolidayKind {
    /// The holiday's name, in Taiwan's words for Taiwan's holidays.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .newYear: language.text("New Year", "元旦")
        case .springFestival: language.text("Lunar New Year", "春節")
        case .peaceMemorial: language.text("Peace Memorial Day", "和平紀念日")
        case .qingming: language.text("Qingming", "清明連假")
        case .labourDay: language.text("Labour Day", "勞動節")
        case .dragonBoat: language.text("Dragon Boat Festival", "端午節")
        case .midAutumn: language.text("Mid-Autumn Festival", "中秋節")
        case .nationalDay: language.text("National Day", "國慶日")
        case .christmas: language.text("Christmas", "聖誕節")
        case .easter: language.text("Easter", "復活節")
        case .thanksgiving: language.text("Thanksgiving", "感恩節")
        case .eidFitr: language.text("Eid al-Fitr", "開齋節")
        case .eidAdha: language.text("Eid al-Adha", "宰牲節")
        case .diwali: language.text("Diwali", "排燈節")
        case .chuseok: language.text("Chuseok", "秋夕")
        case .goldenWeek: language.text("Golden Week", "黃金週")
        case .songkran: language.text("Songkran", "潑水節")
        }
    }
}

/// How the riders of a holiday that has just ended compared with the days
/// before it (decision 154).
public struct HolidayReview: Hashable, Sendable {
    public let kind: HolidayKind
    /// Paying riders a day, on average, while it ran.
    public let riders: Int64
    /// How many more a day than before it, in percent (less when negative).
    public let percent: Int64
}

extension GameWorld {
    /// How many days before a holiday the panels announce it.
    public static let holidayNotice: Int64 = 7

    /// The holidays announced or running, in the station panel's words:
    /// "Lunar New Year: +20% demand on every line, starts in 3 days, lasts 9
    /// days", or "Lunar New Year: +20% demand on every line, 5 more days".
    public func holidayTexts(in language: DisplayLanguage) -> [String] {
        let today = clock.now.seconds / GameTime.secondsPerDay
        return holidays(from: today, through: today + Self.holidayNotice).map { run in
            let percent = (run.boost + 5) / 10
            let title = run.holiday.kind.title(in: language)
            if run.start > today {
                let wait = run.start - today, days = run.end - run.start
                return language.text(
                    "\(title): +\(percent)% demand on every line, starts in \(wait) day\(wait == 1 ? "" : "s"), lasts \(days) day\(days == 1 ? "" : "s")",
                    "\(title)：全線需求 +\(percent)%，\(wait) 天後開始，連續 \(days) 天"
                )
            }
            let left = run.end - today
            return language.text(
                "\(title): +\(percent)% demand on every line, \(left) more day\(left == 1 ? "" : "s")",
                "\(title)：全線需求 +\(percent)%，還有 \(left) 天"
            )
        }
    }

    /// The holiday that ended yesterday and its riders against as many days
    /// before it, from the managed company's days (``CompanyAccounts/days``);
    /// `nil` when none ended yesterday or a day is missing.
    public func holidayReview() -> HolidayReview? {
        let today = clock.now.seconds / GameTime.secondsPerDay
        guard accounts.mode == .management,
              let run = holidays(from: today - 1, through: today - 1).last(where: { $0.end == today }) else { return nil }
        let length = run.end - run.start
        let trips = Dictionary(accounts.days.map { ($0.day, $0.fareTrips) }, uniquingKeysWith: { $1 })
        let during = (run.start..<run.end).compactMap { trips[$0] }
        let before = ((run.start - length)..<run.start).compactMap { trips[$0] }
        guard during.count == length, before.count == length else { return nil }
        let after = during.reduce(0, +), base = before.reduce(0, +)
        guard base > 0 else { return nil }
        return HolidayReview(kind: run.holiday.kind, riders: after / length, percent: ((after - base) * 100 + (after >= base ? base / 2 : -base / 2)) / base)
    }
}

// Decision 162: the weather and typhoons in the station panel's words.

extension Weather {
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .clear: language.text("Clear", "晴")
        case .rain: language.text("Rain", "下雨")
        case .thunderstorm: language.text("Thunderstorms", "雷雨")
        }
    }
}

extension GameWorld {
    /// Today's weather when it is not clear, and the typhoons announced or
    /// blowing over station `id`, in the station panel's words: "Rain today:
    /// −10% demand on every line", "Typhoon: −80% demand here, comes in 2
    /// days, lasts 2 days", or "Typhoon: −80% demand here, 1 more day".
    public func weatherTexts(at id: StationID, in language: DisplayLanguage) -> [String] {
        guard disruptions != nil else { return [] }
        let today = clock.now.seconds / GameTime.secondsPerDay
        var lines: [String] = []
        let weather = weather(onDay: today)
        if weather != .clear {
            let percent = weatherDrop(onDay: today) / 10
            lines.append(language.text(
                "\(weather.title(in: language)) today: −\(percent)% demand on every line",
                "今天\(weather.title(in: language))：全線需求 −\(percent)%"
            ))
        }
        guard let point = station(id: id)?.point else { return lines }
        for typhoon in typhoons(onDay: today) where typhoon.covers(point) {
            let percent = typhoon.drop / 10
            if typhoon.start > today {
                let wait = typhoon.start - today, days = typhoon.end - typhoon.start
                lines.append(language.text(
                    "Typhoon: −\(percent)% demand here, comes in \(wait) day\(wait == 1 ? "" : "s"), lasts \(days) day\(days == 1 ? "" : "s")",
                    "颱風：這站需求 −\(percent)%，\(wait) 天後來襲，持續 \(days) 天"
                ))
            } else {
                let left = typhoon.end - today
                lines.append(language.text(
                    "Typhoon: −\(percent)% demand here, \(left) more day\(left == 1 ? "" : "s")",
                    "颱風：這站需求 −\(percent)%，還有 \(left) 天"
                ))
            }
        }
        return lines
    }
}
