// Taiwan's public holidays worked out for each game year (ARCHITECTURE
// decision 211), after the 紀念日及節日實施條例 (law.moj.gov.tw D0020095, as
// amended in 2025):
//
// - the commemorative days off (article 4): 1 January, 28 February,
//   28 September (Confucius's birthday, Teachers' Day), 10 October,
//   25 October and 25 December;
// - the festivals off (article 6): the Lunar New Year from the day before
//   New Year's Eve to the third day, five days; Children's Day (4 April),
//   Qingming, Labour Day (1 May), the Dragon Boat Festival, Teachers' Day
//   and the Mid-Autumn Festival, a day each; when Children's Day and
//   Qingming fall on one day, Children's Day is the day before, or the day
//   after when that day is a Thursday;
// - a day off that falls on a weekend is made up (article 8), as the
//   Directorate-General of Personnel Administration does: a Saturday's on
//   the working day before, a Sunday's on the working day after, and the
//   Lunar New Year's on the working days after it.
//
// The week is the game's own (`StationDemand.weekday(ofDay:)`, day 0 a
// Monday), so a holiday moves through the week from year to year as a real
// one does, and a run of days off is every day off with the weekend days
// joined to it. Game year 0 is 2026, the year decision 154 took its dates
// from, and each later year the real year after; a date is put on the same
// month and day of the game's 30-day months (the 31st on the 30th).
//
// The lunar dates are the Hong Kong Observatory's Gregorian-lunar tables
// (the lunar calendar reckoned at UTC+8, as Taiwan's is), from 2025 to 2100,
// written by `tools/holiday-calendar/build_taiwan_lunar_dates.py`; a year
// outside them takes the dates of the year a multiple of 19 years away
// inside them (the Metonic cycle, after which the lunar months come back
// within a day or two of the same dates).

/// Taiwan's public holidays, worked out year by year (decision 211).
enum TaiwanHolidays {
    /// Taiwan's code in ``HolidayCalendar/countries``.
    static let country = "TW"
    /// The real year of game year 0.
    static let firstGameYear: Int64 = 2026
    /// The real year of ``lunarDates``' first row.
    static let firstTableYear: Int64 = 2025
    /// Years after which the lunar dates come round again.
    static let cycle: Int64 = 19

    /// For each real year from ``firstTableYear``, the Gregorian month and
    /// day (MMDD) of the Lunar New Year, Qingming, the Dragon Boat Festival
    /// and the Mid-Autumn Festival.
    static let lunarDates: [[Int]] = [
        // 2025 to 2100: Lunar New Year, Qingming, Dragon Boat, Mid-Autumn (MMDD).
        [129, 404, 531, 1006], // 2025
        [217, 405, 619, 925], // 2026
        [206, 405, 609, 915], // 2027
        [126, 404, 528, 1003], // 2028
        [213, 404, 616, 922], // 2029
        [203, 405, 605, 912], // 2030
        [123, 405, 624, 1001], // 2031
        [211, 404, 612, 919], // 2032
        [131, 404, 601, 908], // 2033
        [219, 405, 620, 927], // 2034
        [208, 405, 610, 916], // 2035
        [128, 404, 530, 1004], // 2036
        [215, 404, 618, 924], // 2037
        [204, 405, 607, 913], // 2038
        [124, 405, 527, 1002], // 2039
        [212, 404, 614, 920], // 2040
        [201, 404, 603, 910], // 2041
        [122, 404, 622, 928], // 2042
        [210, 405, 611, 917], // 2043
        [130, 404, 531, 1005], // 2044
        [217, 404, 619, 925], // 2045
        [206, 404, 608, 915], // 2046
        [126, 405, 529, 1004], // 2047
        [214, 404, 615, 922], // 2048
        [202, 404, 604, 911], // 2049
        [123, 404, 623, 930], // 2050
        [211, 405, 613, 919], // 2051
        [201, 404, 601, 907], // 2052
        [219, 404, 620, 926], // 2053
        [208, 404, 610, 916], // 2054
        [128, 405, 530, 1005], // 2055
        [215, 404, 617, 924], // 2056
        [204, 404, 606, 913], // 2057
        [124, 404, 625, 1002], // 2058
        [212, 405, 614, 921], // 2059
        [202, 404, 603, 909], // 2060
        [121, 404, 622, 928], // 2061
        [209, 404, 611, 917], // 2062
        [129, 405, 601, 1006], // 2063
        [217, 404, 619, 925], // 2064
        [205, 404, 608, 915], // 2065
        [126, 404, 528, 1003], // 2066
        [214, 405, 616, 923], // 2067
        [203, 404, 604, 911], // 2068
        [123, 404, 623, 929], // 2069
        [211, 404, 613, 919], // 2070
        [131, 405, 602, 908], // 2071
        [219, 404, 620, 926], // 2072
        [207, 404, 610, 916], // 2073
        [127, 404, 530, 1005], // 2074
        [215, 404, 617, 924], // 2075
        [205, 404, 606, 912], // 2076
        [124, 404, 624, 1001], // 2077
        [212, 404, 614, 920], // 2078
        [202, 404, 604, 910], // 2079
        [122, 404, 622, 928], // 2080
        [209, 404, 611, 917], // 2081
        [129, 404, 601, 1006], // 2082
        [217, 404, 619, 926], // 2083
        [206, 404, 607, 914], // 2084
        [126, 404, 527, 1003], // 2085
        [214, 404, 615, 922], // 2086
        [203, 404, 605, 911], // 2087
        [124, 404, 623, 929], // 2088
        [210, 404, 613, 918], // 2089
        [130, 404, 602, 908], // 2090
        [218, 404, 621, 927], // 2091
        [207, 404, 609, 916], // 2092
        [127, 404, 529, 1005], // 2093
        [215, 404, 617, 924], // 2094
        [205, 404, 606, 913], // 2095
        [125, 404, 624, 930], // 2096
        [212, 404, 614, 920], // 2097
        [201, 404, 604, 909], // 2098
        [121, 404, 623, 929], // 2099
        [209, 405, 612, 918], // 2100
    ]

    /// The lunar dates of real year `year`, from the table or the year a
    /// multiple of ``cycle`` years away inside it.
    static func lunarDates(ofRealYear year: Int64) -> [Int] {
        let last = firstTableYear + Int64(lunarDates.count) - 1
        var inside = year
        if inside > last {
            inside -= (inside - last + cycle - 1) / cycle * cycle
        } else if inside < firstTableYear {
            inside += (firstTableYear - inside + cycle - 1) / cycle * cycle
        }
        return lunarDates[Int(inside - firstTableYear)]
    }

    /// The days holidays are counted on: which day a date of a year is,
    /// and which day of the week a day is (0 Sunday to 6 Saturday). The
    /// game's (``game``), or the real calendar's for checking the rules
    /// against a real year's days off.
    struct Week: Sendable {
        /// The day of month and day (MMDD) of a year.
        let day: @Sendable (_ mmdd: Int, _ year: Int64) -> Int64
        /// The day of the week of a day.
        let weekday: @Sendable (_ day: Int64) -> Int

        /// The game's: 30-day months (the 31st on the 30th), day 0 a Monday.
        static let game = Week(
            day: { mmdd, year in year * FinancePeriod.year.days + Int64((mmdd / 100 - 1) * 30 + min(mmdd % 100, 30) - 1) },
            weekday: { StationDemand.weekday(ofDay: $0) }
        )

        func isWeekend(_ day: Int64) -> Bool {
            let weekday = weekday(day)
            return weekday == 0 || weekday == 6
        }
    }

    /// The game day of month and day `mmdd` in game year `year`.
    static func day(_ mmdd: Int, inYear year: Int64) -> Int64 {
        Week.game.day(mmdd, year)
    }

    /// Year `year`'s days off (game year 0 is 2026), each with its holiday,
    /// on `week`.
    static func daysOff(inYear year: Int64, on week: Week = .game) -> [(day: Int64, kind: HolidayKind)] {
        let lunar = lunarDates(ofRealYear: firstGameYear + year)
        var off: [(day: Int64, kind: HolidayKind)] = []
        var taken: Set<Int64> = []
        func isFree(_ day: Int64) -> Bool {
            !week.isWeekend(day) && !taken.contains(day)
        }
        func take(_ day: Int64, _ kind: HolidayKind) {
            off.append((day, kind))
            taken.insert(day)
        }
        // The days off of one day, by date; Children's Day and Qingming
        // keep the Qingming holiday's name.
        let qingming = lunar[1]
        var children = 404
        if qingming == 404 {
            children = week.weekday(week.day(404, year)) == 4 ? 405 : 403
        }
        let dates: [(Int, HolidayKind)] = [
            (101, .newYear), (228, .peaceMemorial), (children, .qingming), (qingming, .qingming), (501, .labourDay),
            (lunar[2], .dragonBoat), (lunar[3], .midAutumn), (928, .teachersDay), (1010, .nationalDay),
            (1025, .retrocessionDay), (1225, .constitutionDay),
        ]
        let single = dates.map { (day: week.day($0.0, year), kind: $0.1) }.sorted { $0.day < $1.day }
        // The Lunar New Year (the day before New Year's Eve to the third
        // day) and the holidays on working days first, on their days; then
        // a weekend's made up: the Lunar New Year's on the working days
        // after it, a Saturday's on the working day before, a Sunday's on
        // the working day after.
        let newYear = week.day(lunar[0], year)
        let spring = (newYear - 2)...(newYear + 2)
        for day in spring {
            take(day, .springFestival)
        }
        for holiday in single where !week.isWeekend(holiday.day) && !taken.contains(holiday.day) {
            take(holiday.day, holiday.kind)
        }
        var madeUp = newYear + 3
        for day in spring where week.isWeekend(day) {
            while !isFree(madeUp) {
                madeUp += 1
            }
            take(madeUp, .springFestival)
        }
        for holiday in single where week.isWeekend(holiday.day) {
            let step: Int64 = week.weekday(holiday.day) == 6 ? -1 : 1
            var day = holiday.day + step
            while !isFree(day) {
                day += step
            }
            take(day, holiday.kind)
        }
        return off.sorted { $0.day < $1.day }
    }

    /// The runs of days off on any day from `first` through `last`, by
    /// start: each the days off with the weekend days joined to them, named
    /// after the holiday among them that adds the most (the first when two
    /// add as much), at `level`.
    static func runs(from first: Int64, through last: Int64, level: DisruptionLevel) -> [HolidayRun] {
        // A run is never longer than a few weeks, so one beginning or
        // ending in the margin is whole.
        let margin: Int64 = 31
        let low = first - margin, high = last + margin
        let year = FinancePeriod.year.days
        var off: [Int64: HolidayKind] = [:]
        for gameYear in CompanyAccounts.floorDivide(low, year)...CompanyAccounts.floorDivide(high, year) {
            for (day, kind) in daysOff(inYear: gameYear) where off[day].map({ boost(of: $0) < boost(of: kind) }) ?? true {
                off[day] = kind
            }
        }
        var runs: [HolidayRun] = []
        var day = low
        while day <= high {
            guard off[day] != nil || StationDemand.isWeekend(day: day) else {
                day += 1
                continue
            }
            let start = day
            var kind: HolidayKind?
            while day <= high, off[day] != nil || StationDemand.isWeekend(day: day) {
                if let today = off[day], kind.map({ boost(of: $0) < boost(of: today) }) ?? true {
                    kind = today
                }
                day += 1
            }
            if let kind, day > first, start <= last {
                let dayOfYear = start - CompanyAccounts.floorDivide(start, year) * year
                let base = boost(of: kind)
                let holiday = Holiday(kind, Int(dayOfYear / 30) + 1, Int(dayOfYear % 30) + 1, days: day - start, boost: base)
                runs.append(HolidayRun(holiday: holiday, start: start, end: day, boost: level.scaled(base)))
            }
        }
        return runs
    }

    /// What `kind` adds to demand at the standard level: its row's in
    /// ``HolidayCalendar/countries``.
    static func boost(of kind: HolidayKind) -> Int64 {
        HolidayCalendar.countries[country]?.first { $0.kind == kind }?.boost ?? 0
    }
}
