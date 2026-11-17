import Foundation
import GameCore

// Decision 813: where the sun stands over the 3D map's own place on the
// game's day, so sunrise and sunset move with the seasons and with the
// latitude (Taipei's December dusk an hour and a half before June's,
// Rovaniemi's December noon a low glow). Until now the light put the sun up
// at 06:00 and down at 18:00 everywhere, every day.
//
// The sun's position is the NOAA Solar Calculator's (a work of the United
// States government), as `Railway/rail-reference/regions/taiwan/source/
// rail-3d/environment/sun.mjs` writes it (`sunPosition`), translated line
// for line; sunrise and sunset are the same calculator's hour angle at the
// standard -0.833° (refraction and the sun's half disc), turned twice at
// the moment found. Only drawing: the date and the clock are GameCore's,
// read and never written, and nothing here is saved.

/// Decision 813: the place a 3D map's sky is worked out for.
public struct Map3DSunPlace: Hashable, Sendable {
    /// Degrees, north and east positive.
    public let latitude: Double
    public let longitude: Double
    /// The clock's offset from UTC, minutes, out of and in summer time
    /// (``utcOffsetMinutes(onDay:)``).
    public let standardOffset: Int
    public let summerOffset: Int

    public init(latitude: Double, longitude: Double, standardOffset: Int, summerOffset: Int? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.standardOffset = standardOffset
        self.summerOffset = summerOffset ?? standardOffset
    }

    /// Taipei Main Station, for a map with no anchor (the generated ones).
    public static let taipei = Map3DSunPlace(latitude: 25.0478, longitude: 121.5170, standardOffset: 480)

    /// The place of `world`'s map.
    public init(world: GameWorld) {
        self = world.geoAnchor.map(Self.init(anchor:)) ?? .taipei
    }

    /// The place at `anchor`, on its clock: UTC+8 in Taiwan and Hong Kong
    /// (decision 802's box), Finland's UTC+2 with summer time (UTC+3), and
    /// elsewhere the nearest whole hour of its longitude.
    public init(anchor: GeoAnchor) {
        let latitude = Double(anchor.latitude) / 10_000_000, longitude = Double(anchor.longitude) / 10_000_000
        let finland = 59.5...70.2 ~= latitude && 19.0...31.6 ~= longitude
        let chinaCoast = 21.5...26.5 ~= latitude && 113.8...122.5 ~= longitude
        let offset = chinaCoast ? 480 : finland ? 120 : Int((longitude / 15).rounded()) * 60
        self.init(latitude: latitude, longitude: longitude, standardOffset: offset, summerOffset: finland ? 180 : nil)
    }

    /// Europe's summer time, 2026's dates: from the last Sunday of March
    /// (29 March, day 88) to the last Sunday of October (25 October, day
    /// 298). The game's years have no weekdays of the real calendar's, so
    /// the one year's dates stand for every year.
    public static let summerDays = 88..<298

    /// The clock's offset on `day` (1 to 365) of the real year.
    public func utcOffsetMinutes(onDay day: Int) -> Int {
        Self.summerDays ~= day ? summerOffset : standardOffset
    }
}

/// Decision 813: the sun over a place.
public enum Map3DSunPath {
    /// Where the sun stands: degrees above the horizon (no refraction) and
    /// round from the north through the east.
    public struct Position: Hashable, Sendable {
        public let elevation: Double
        public let azimuth: Double
        /// The hour angle, degrees: 0 at the true noon, negative in the
        /// morning, ±180 at the true midnight.
        public let hourAngle: Double
        /// The sun's declination, degrees.
        public let declination: Double

        /// The day's highest elevation (no refraction) at `latitude`: the
        /// true noon's.
        public func highest(atLatitude latitude: Double) -> Double { 90 - abs(latitude - declination) }
    }

    /// The day's sunrise, true noon and sunset, minutes of the place's
    /// clock; `nil` for a day the sun does not rise or does not set.
    public struct Day: Hashable, Sendable {
        public let sunrise: Double?
        public let noon: Double
        public let sunset: Double?
        /// The sun's elevation at its highest and its lowest, degrees.
        public let highest: Double
        public let lowest: Double

        /// Neither up nor down all day: up all day (white nights).
        public var upAllDay: Bool { sunrise == nil && sunset == nil && lowest > Map3DSunPath.horizon }
        /// Down all day (polar night).
        public var downAllDay: Bool { sunrise == nil && sunset == nil && highest <= Map3DSunPath.horizon }
    }

    /// The real year's day (1 to 365) of game `day`: its month and day of
    /// the month as the game shows them (``GameDate``), on the real
    /// calendar's months; the game's 29 and 30 February and 31st days that
    /// do not exist are the month's last real day.
    public static func realDayOfYear(gameDay day: Int64) -> Int {
        let date = GameDate(day: day)
        return monthStarts[date.month - 1] + min(date.dayOfMonth, monthLengths[date.month - 1])
    }

    static let monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    static let monthStarts: [Int] = monthLengths.indices.map { monthLengths.prefix($0).reduce(0, +) }

    /// The elevation sunrise and sunset are taken at: the sun's upper edge
    /// on the horizon, with the air's refraction (the almanacs').
    public static let horizon = -0.833

    /// The Julian day of 1 January 2026, 00:00 UTC: every game year is
    /// worked out as 2026 (the sun's yearly path moves by seconds of arc a
    /// year, nothing a player can see).
    static let yearStart = 2_461_041.5

    /// Where the sun stands at `minute` (of the place's clock, may run
    /// past the day's ends) on `day` (1 to 365) of the year.
    public static func position(day: Int, minute: Double, at place: Map3DSunPlace) -> Position {
        let utcMinutes = minute - Double(place.utcOffsetMinutes(onDay: day))
        return position(julianDay: yearStart + Double(day - 1) + utcMinutes / 1_440, latitude: place.latitude, longitude: place.longitude)
    }

    /// sun.mjs's `sunPosition`, from a Julian day instead of UTC
    /// milliseconds.
    static func position(julianDay jd: Double, latitude: Double, longitude: Double) -> Position {
        let sun = Self.sun(julianDay: jd)
        var utcMinutes = (jd + 0.5).truncatingRemainder(dividingBy: 1) * 1_440
        if utcMinutes < 0 { utcMinutes += 1_440 }
        var trueSolar = (utcMinutes + sun.equationOfTime + 4 * longitude + 1_440).truncatingRemainder(dividingBy: 1_440)
        if trueSolar < 0 { trueSolar += 1_440 }
        let hourAngle = trueSolar / 4 < 0 ? trueSolar / 4 + 180 : trueSolar / 4 - 180
        let lat = latitude * rad, dec = sun.declination * rad, ha = hourAngle * rad
        let cosZenith = sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha)
        let zenith = acos(min(max(cosZenith, -1), 1))
        let elevation = 90 - zenith / rad
        let denominator = cos(lat) * sin(zenith)
        var azimuth: Double
        if abs(denominator) > 1e-9 {
            let c = min(max((sin(lat) * cos(zenith) - sin(dec)) / denominator, -1), 1)
            azimuth = hourAngle > 0 ? (acos(c) / rad + 180).truncatingRemainder(dividingBy: 360)
                : (540 - acos(c) / rad).truncatingRemainder(dividingBy: 360)
        } else {
            azimuth = latitude > 0 ? 180 : 0
        }
        if azimuth < 0 { azimuth += 360 }
        return Position(elevation: elevation, azimuth: azimuth, hourAngle: hourAngle, declination: sun.declination)
    }

    /// The sun's declination (degrees) and the equation of time (minutes)
    /// at Julian day `jd`, sun.mjs's lines.
    static func sun(julianDay jd: Double) -> (declination: Double, equationOfTime: Double) {
        let t = (jd - 2_451_545) / 36_525
        let l0 = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m * rad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m * rad) * (0.019993 - 0.000101 * t) + sin(3 * m * rad) * 0.000289
        let omega = 125.04 - 1_934.136 * t
        let apparentLongitude = l0 + c - 0.00569 - 0.00478 * sin(omega * rad)
        let seconds = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))
        let obliquity = 23 + (26 + seconds / 60) / 60 + 0.00256 * cos(omega * rad)
        let declination = asin(sin(obliquity * rad) * sin(apparentLongitude * rad)) / rad
        let y = pow(tan(obliquity / 2 * rad), 2)
        let a = y * sin(2 * l0 * rad) - 2 * e * sin(m * rad) + 4 * e * y * sin(m * rad) * cos(2 * l0 * rad)
        let b = 0.5 * y * y * sin(4 * l0 * rad) + 1.25 * e * e * sin(2 * m * rad)
        return (declination, 4 * (a - b) / rad)
    }

    /// The day's sunrise, true noon and sunset at `place`.
    public static func day(_ day: Int, at place: Map3DSunPlace) -> Day {
        let offset = Double(place.utcOffsetMinutes(onDay: day))
        // The true noon, and the elevation then and at the true midnight.
        var noon = 720.0
        for _ in 0..<2 {
            noon = 720 - 4 * place.longitude - sun(julianDay: yearStart + Double(day - 1) + (noon - offset) / 1_440).equationOfTime + offset
        }
        let highest = position(day: day, minute: noon, at: place).elevation
        let lowest = position(day: day, minute: noon - 720, at: place).elevation
        func crossing(_ side: Double) -> Double? {
            var minute = noon + side * 360
            for _ in 0..<3 {
                let jd = yearStart + Double(day - 1) + (minute - offset) / 1_440
                let sun = Self.sun(julianDay: jd)
                let lat = place.latitude * rad, dec = sun.declination * rad
                let cosine = (cos((90 - horizon) * rad) - sin(lat) * sin(dec)) / (cos(lat) * cos(dec))
                guard (-1...1).contains(cosine) else { return nil }
                minute = 720 - 4 * (place.longitude - side * acos(cosine) / rad) - sun.equationOfTime + offset
            }
            return minute
        }
        return Day(sunrise: crossing(-1), noon: noon, sunset: crossing(1), highest: highest, lowest: lowest)
    }

    static let rad = Double.pi / 180
}
