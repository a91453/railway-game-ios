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

// MARK: - The moon (decision 942, MOON-PHASE)

// Decision 942: the moon where it stands and how much of it is lit, so the
// sky's moon waxes and wanes through the month and rises later each night,
// in place of decision 813's full moon always across the sky from the sun.
//
// The series are Meeus's (Astronomical Algorithms, chapters 22, 25 and
// 47: the moon's 60 + 60 periodic terms, the nutation's four, the sun's
// apparent longitude, the sidereal time), as the owner's landscape engine
// writes them (`Railway/rail-reference/regions/taiwan/source/
// landscape-engine/engine/shared/sky-ephem.mjs`: `jdTw`, `moonEcliptic`,
// `nutation`, `sunEcliptic`, `gmst`, `moonAt`), translated line for line;
// angles in degrees, distances in kilometres, as there.
extension Map3DSunPath {
    /// Where the moon stands and how it is lit.
    public struct Moon: Hashable, Sendable {
        /// Degrees above the horizon (no refraction), and round from the
        /// north through the east: as seen from the place (topocentric).
        public let elevation: Double
        public let azimuth: Double
        /// The share of the disc lit, 0 (new) to 1 (full) (`k`).
        public let illuminated: Double
        /// The phase angle, degrees: 180 at new moon, 0 at full (`phase`).
        public let phaseAngle: Double
        /// The way from the moon toward the sun, east, north and up (`sun`):
        /// the side of the disc that is lit.
        public let towardSun: SIMD3<Double>
        /// The moon's elongation east of the sun, degrees, 0 to 360: under
        /// 180 waxing (evening sky), over it waning.
        public let elongation: Double

        /// Waxing (the lit side toward the evening sun).
        public var waxing: Bool { elongation < 180 }
    }

    /// `jdTw`: the Julian day of `hour` (Taiwan's clock, UTC+8) on `day`
    /// `month` `year` of the Gregorian calendar.
    public static func julianDayTaiwan(year: Int, month: Int, day: Int, hour: Double) -> Double {
        // Date.UTC(y, m - 1, d) / 864e5: the days from 1970-01-01.
        let a = (14 - month) / 12, y = year + 4800 - a, m = month + 12 * a - 3
        let jdn = day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32_045
        return Double(jdn) - 0.5 + (hour - 8) / 24
    }

    /// ΔT, seconds (`DT_S`), the kilometres in an astronomical unit and
    /// the earth's radius (`AU_KM`, `RE_KM`), and its flattening (`BA`).
    static let deltaT = 69.2, astronomicalUnit = 149_597_870.7, earthRadius = 6_378.14
    static let earthAxisRatio = 1 - 1 / 298.257

    static func degrees(_ x: Double) -> Double { (x.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
    static func sind(_ x: Double) -> Double { sin(x * rad) }
    static func cosd(_ x: Double) -> Double { cos(x * rad) }

    /// `moonEcliptic`: the moon's geocentric ecliptic longitude and
    /// latitude (degrees, of the date, without nutation) and its distance
    /// (km), at `t` Julian centuries from J2000 (dynamical time).
    static func moonEcliptic(_ t: Double) -> (longitude: Double, latitude: Double, distance: Double) {
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t
        let lp = degrees(218.3164477 + 481_267.88123421 * t - 0.0015786 * t2 + t3 / 538_841 - t4 / 65_194_000)
        let d = degrees(297.8501921 + 445_267.1114034 * t - 0.0018819 * t2 + t3 / 545_868 - t4 / 113_065_000)
        let m = degrees(357.5291092 + 35_999.0502909 * t - 0.0001536 * t2 + t3 / 24_490_000)
        let mp = degrees(134.9633964 + 477_198.8675055 * t + 0.0087414 * t2 + t3 / 69_699 - t4 / 14_712_000)
        let f = degrees(93.272095 + 483_202.0175233 * t - 0.0036539 * t2 - t3 / 3_526_000 + t4 / 863_310_000)
        let a1 = degrees(119.75 + 131.849 * t), a2 = degrees(53.09 + 479_264.29 * t), a3 = degrees(313.45 + 481_266.484 * t)
        let e = 1 - 0.002516 * t - 0.0000074 * t2
        func eccentricity(_ m: Double) -> Double { m == 0 ? 1 : abs(m) == 1 ? e : e * e }
        var sl = 0.0, sr = 0.0, sb = 0.0
        for row in moonLongitudeTerms {
            let a = row[0] * d + row[1] * m + row[2] * mp + row[3] * f, factor = eccentricity(row[1])
            sl += row[4] * factor * sind(a)
            sr += row[5] * factor * cosd(a)
        }
        for row in moonLatitudeTerms {
            let a = row[0] * d + row[1] * m + row[2] * mp + row[3] * f
            sb += row[4] * eccentricity(row[1]) * sind(a)
        }
        sl += 3_958 * sind(a1) + 1_962 * sind(lp - f) + 318 * sind(a2)
        sb += -2_235 * sind(lp) + 382 * sind(a3) + 175 * sind(a1 - f) + 175 * sind(a1 + f) + 127 * sind(lp - mp) - 115 * sind(lp + mp)
        return (lp + sl / 1e6, sb / 1e6, 385_000.56 + sr / 1e3)
    }

    /// `nutation`: the nutation in longitude and in obliquity and the true
    /// obliquity, degrees.
    static func nutation(_ t: Double) -> (longitude: Double, obliquity: Double) {
        let om = 125.04452 - 1_934.136261 * t, l = 280.4665 + 36_000.7698 * t, lp = 218.3165 + 481_267.8813 * t
        let dpsi = (-17.2 * sind(om) - 1.32 * sind(2 * l) - 0.23 * sind(2 * lp) + 0.21 * sind(2 * om)) / 3_600
        let deps = (9.2 * cosd(om) + 0.57 * cosd(2 * l) + 0.1 * cosd(2 * lp) - 0.09 * cosd(2 * om)) / 3_600
        let eps0 = 23.4392911111 - (46.815 * t + 0.00059 * t * t - 0.001813 * t * t * t) / 3_600
        return (dpsi, eps0 + deps)
    }

    /// `sunEcliptic`: the sun's apparent longitude (degrees) and distance
    /// (km).
    static func sunEcliptic(_ t: Double, nutation dpsi: Double) -> (longitude: Double, distance: Double) {
        let l0 = 280.46646 + 36_000.76983 * t + 0.0003032 * t * t
        let m = 357.52911 + 35_999.05029 * t - 0.0001537 * t * t
        let e = 0.016708634 - 0.000042037 * t - 0.0000001267 * t * t
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sind(m) + (0.019993 - 0.000101 * t) * sind(2 * m) + 0.000289 * sind(3 * m)
        let r = 1.000001018 * (1 - e * e) / (1 + e * cosd(m + c))
        return (degrees(l0 + c + dpsi - 20.4898 / 3_600 / r), r * astronomicalUnit)
    }

    /// `gmst`: Greenwich mean sidereal time at Julian day `jd`, degrees.
    static func gmst(_ jd: Double) -> Double {
        let t = jd - 2_451_545, c = t / 36_525
        return degrees(280.46061837 + 360.98564736629 * t + 0.000387933 * c * c - c * c * c / 38_710_000)
    }

    /// `moonAt`: the moon over `latitude`, `longitude` at Julian day `jd`
    /// (UTC), at sea level.
    public static func moonPosition(julianDay jd: Double, latitude: Double, longitude: Double) -> Moon {
        let t = (jd + deltaT / 86_400 - 2_451_545) / 36_525, nu = nutation(t)
        let lunar = moonEcliptic(t), sun = sunEcliptic(t, nutation: nu.longitude)
        let siderealTime = degrees(gmst(jd) + nu.longitude * cosd(nu.obliquity) + longitude)
        return moon(longitude: lunar.longitude + nu.longitude, latitude: lunar.latitude, distance: lunar.distance,
                    sunLongitude: sun.longitude, sunDistance: sun.distance, obliquity: nu.obliquity,
                    siderealTime: siderealTime, siteLatitude: latitude,
                    elongation: degrees(lunar.longitude + nu.longitude - sun.longitude))
    }

    /// `moonAt`'s second half: from the geocentric moon and sun to the
    /// place's sky (`eclVec`, `observer`, `toENU`).
    static func moon(longitude: Double, latitude: Double, distance: Double, sunLongitude: Double, sunDistance: Double,
                     obliquity eps: Double, siderealTime th: Double, siteLatitude ph: Double, elongation: Double) -> Moon {
        func ecliptic(_ lon: Double, _ lat: Double) -> SIMD3<Double> {
            let x = cosd(lat) * cosd(lon), y = cosd(lat) * sind(lon), z = sind(lat)
            return SIMD3(x, y * cosd(eps) - z * sind(eps), y * sind(eps) + z * cosd(eps))
        }
        func toENU(_ v: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(-sind(th) * v.x + cosd(th) * v.y,
                  -sind(ph) * cosd(th) * v.x - sind(ph) * sind(th) * v.y + cosd(ph) * v.z,
                  cosd(ph) * cosd(th) * v.x + cosd(ph) * sind(th) * v.y + sind(ph) * v.z)
        }
        func unit(_ v: SIMD3<Double>) -> SIMD3<Double> { v / (v * v).sum().squareRoot() }
        let u = atan(earthAxisRatio * tan(ph * rad))
        let observer = SIMD3(earthRadius * cos(u) * cosd(th), earthRadius * cos(u) * sind(th), earthRadius * earthAxisRatio * sin(u))
        let toMoon = ecliptic(longitude, latitude) * distance - observer
        let toSun = ecliptic(sunLongitude, 0) * sunDistance - observer
        let dir = unit(toENU(toMoon))
        let moonToSun = unit(toSun - toMoon)
        let cosI = -(moonToSun * unit(toMoon)).sum()
        let elevation = asin(min(max(dir.z, -1), 1)) / rad
        return Moon(elevation: elevation, azimuth: degrees(atan2(dir.x, dir.y) / rad), illuminated: (1 + cosI) / 2,
                    phaseAngle: acos(min(max(cosI, -1), 1)) / rad, towardSun: unit(toENU(moonToSun)), elongation: elongation)
    }

    /// The Julian day (UTC) game day 0 begins at on the place's clock: 1
    /// January 2026 (``yearStart``). The moon's month runs on from there
    /// day after day, so its phases follow on through the game's 360-day
    /// years without a step (``moonPosition(date:place:)``).
    static let moonEpoch = yearStart

    /// The days of a real (tropical) year: the sun's longitude a game year
    /// is worked out on runs once round in 360 game days.
    static let tropicalYear = 365.2422

    /// Decision 942: the moon over `place` at game time `date`.
    ///
    /// The game's years are 360 days and its sun (``position(day:minute:at:)``)
    /// stands every year where it stood in 2026, so the real calendar's
    /// moon cannot be read off the game's date. Two clocks: the moon's age
    /// (how far east of the sun it stands, its latitude and distance) is
    /// worked out at 1 January 2026 plus the game days since day 0, so the
    /// month runs on without a step and a full moon follows a new one in
    /// 14.8 days; the sun's longitude and the sky's turn (the sidereal time)
    /// are the game year's, the season stretched from 360 days to the real
    /// year's, the hour angle the clock's as the sun's own. So the moon
    /// stands across the drawn sun at full and beside it at new, and it
    /// moves on smoothly, past midnight and the year's end too.
    public static func moonPosition(date: GameTime, place: Map3DSunPlace) -> Moon {
        let secondsPerDay = Double(GameTime.secondsPerDay)
        let gameDay = GameDate.floorDivide(date.seconds, GameTime.secondsPerDay)
        let offset = Double(place.utcOffsetMinutes(onDay: realDayOfYear(gameDay: gameDay))) / 1_440
        // UTC days since game day 0's local midnight.
        let days = Double(date.seconds) / secondsPerDay - offset
        let age = moonEpoch + days
        let tAge = (age + deltaT / 86_400 - 2_451_545) / 36_525
        let moonNow = moonEcliptic(tAge), nuAge = nutation(tAge)
        let elongation = degrees(moonNow.longitude + nuAge.longitude - sunEcliptic(tAge, nutation: nuAge.longitude).longitude)
        // The season: the game year's day stretched to the real year's.
        let year = Double(FinancePeriod.year.days)
        var ofYear = days.truncatingRemainder(dividingBy: year)
        if ofYear < 0 { ofYear += year }
        let season = yearStart + ofYear * tropicalYear / year
        let tSeason = (season + deltaT / 86_400 - 2_451_545) / 36_525, nu = nutation(tSeason)
        let sun = sunEcliptic(tSeason, nutation: nu.longitude)
        // The sky's turn: the sun's right ascension plus its hour angle
        // by the clock (sun.mjs's true solar time).
        var utcMinutes = (days - days.rounded(.down)) * 1_440
        if utcMinutes < 0 { utcMinutes += 1_440 }
        let hourAngle = (utcMinutes + Self.sun(julianDay: season).equationOfTime + 4 * place.longitude) / 4 - 180
        let sunRightAscension = atan2(cosd(nu.obliquity) * sind(sun.longitude), cosd(sun.longitude)) / rad
        return moon(longitude: degrees(sun.longitude + elongation), latitude: moonNow.latitude, distance: moonNow.distance,
                    sunLongitude: sun.longitude, sunDistance: sun.distance, obliquity: nu.obliquity,
                    siderealTime: degrees(sunRightAscension + hourAngle), siteLatitude: place.latitude, elongation: elongation)
    }

    /// `ML` and `MB`: the moon's periodic terms in longitude and distance
    /// (D, M, M′, F, Σl in 10⁻⁶ degree, Σr in metres) and in latitude
    /// (D, M, M′, F, Σb in 10⁻⁶ degree), Meeus's tables 47.A and 47.B.
    static let moonLongitudeTerms: [[Double]] = [
        [0, 0, 1, 0, 6288774, -20905355],
        [2, 0, -1, 0, 1274027, -3699111],
        [2, 0, 0, 0, 658314, -2955968],
        [0, 0, 2, 0, 213618, -569925],
        [0, 1, 0, 0, -185116, 48888],
        [0, 0, 0, 2, -114332, -3149],
        [2, 0, -2, 0, 58793, 246158],
        [2, -1, -1, 0, 57066, -152138],
        [2, 0, 1, 0, 53322, -170733],
        [2, -1, 0, 0, 45758, -204586],
        [0, 1, -1, 0, -40923, -129620],
        [1, 0, 0, 0, -34720, 108743],
        [0, 1, 1, 0, -30383, 104755],
        [2, 0, 0, -2, 15327, 10321],
        [0, 0, 1, 2, -12528, 0],
        [0, 0, 1, -2, 10980, 79661],
        [4, 0, -1, 0, 10675, -34782],
        [0, 0, 3, 0, 10034, -23210],
        [4, 0, -2, 0, 8548, -21636],
        [2, 1, -1, 0, -7888, 24208],
        [2, 1, 0, 0, -6766, 30824],
        [1, 0, -1, 0, -5163, -8379],
        [1, 1, 0, 0, 4987, -16675],
        [2, -1, 1, 0, 4036, -12831],
        [2, 0, 2, 0, 3994, -10445],
        [4, 0, 0, 0, 3861, -11650],
        [2, 0, -3, 0, 3665, 14403],
        [0, 1, -2, 0, -2689, -7003],
        [2, 0, -1, 2, -2602, 0],
        [2, -1, -2, 0, 2390, 10056],
        [1, 0, 1, 0, -2348, 6322],
        [2, -2, 0, 0, 2236, -9884],
        [0, 1, 2, 0, -2120, 5751],
        [0, 2, 0, 0, -2069, 0],
        [2, -2, -1, 0, 2048, -4950],
        [2, 0, 1, -2, -1773, 4130],
        [2, 0, 0, 2, -1595, 0],
        [4, -1, -1, 0, 1215, -3958],
        [0, 0, 2, 2, -1110, 0],
        [3, 0, -1, 0, -892, 3258],
        [2, 1, 1, 0, -810, 2616],
        [4, -1, -2, 0, 759, -1897],
        [0, 2, -1, 0, -713, -2117],
        [2, 2, -1, 0, -700, 2354],
        [2, 1, -2, 0, 691, 0],
        [2, -1, 0, -2, 596, 0],
        [4, 0, 1, 0, 549, -1423],
        [0, 0, 4, 0, 537, -1117],
        [4, -1, 0, 0, 520, -1571],
        [1, 0, -2, 0, -487, -1739],
        [2, 1, 0, -2, -399, 0],
        [0, 0, 2, -2, -381, -4421],
        [1, 1, 1, 0, 351, 0],
        [3, 0, -2, 0, -340, 0],
        [4, 0, -3, 0, 330, 0],
        [2, -1, 2, 0, 327, 0],
        [0, 2, 1, 0, -323, 1165],
        [1, 1, -1, 0, 299, 0],
        [2, 0, 3, 0, 294, 0],
        [2, 0, -1, -2, 0, 8752],
    ]
    static let moonLatitudeTerms: [[Double]] = [
        [0, 0, 0, 1, 5128122],
        [0, 0, 1, 1, 280602],
        [0, 0, 1, -1, 277693],
        [2, 0, 0, -1, 173237],
        [2, 0, -1, 1, 55413],
        [2, 0, -1, -1, 46271],
        [2, 0, 0, 1, 32573],
        [0, 0, 2, 1, 17198],
        [2, 0, 1, -1, 9266],
        [0, 0, 2, -1, 8822],
        [2, -1, 0, -1, 8216],
        [2, 0, -2, -1, 4324],
        [2, 0, 1, 1, 4200],
        [2, 1, 0, -1, -3359],
        [2, -1, -1, 1, 2463],
        [2, -1, 0, 1, 2211],
        [2, -1, -1, -1, 2065],
        [0, 1, -1, -1, -1870],
        [4, 0, -1, -1, 1828],
        [0, 1, 0, 1, -1794],
        [0, 0, 0, 3, -1749],
        [0, 1, -1, 1, -1565],
        [1, 0, 0, 1, -1491],
        [0, 1, 1, 1, -1475],
        [0, 1, 1, -1, -1410],
        [0, 1, 0, -1, -1344],
        [1, 0, 0, -1, -1335],
        [0, 0, 3, 1, 1107],
        [4, 0, 0, -1, 1021],
        [4, 0, -1, 1, 833],
        [0, 0, 1, -3, 777],
        [4, 0, -2, 1, 671],
        [2, 0, 0, -3, 607],
        [2, 0, 2, -1, 596],
        [2, -1, 1, -1, 491],
        [2, 0, -2, 1, -451],
        [0, 0, 3, -1, 439],
        [2, 0, 2, 1, 422],
        [2, 0, -3, -1, 421],
        [2, 1, -1, 1, -366],
        [2, 1, 0, 1, -351],
        [4, 0, 0, 1, 331],
        [2, -1, 1, 1, 315],
        [2, -2, 0, -1, 302],
        [0, 0, 1, 3, -283],
        [2, 1, 1, -1, -229],
        [1, 1, 0, -1, 223],
        [1, 1, 0, 1, 223],
        [0, 1, -2, -1, -220],
        [2, 1, -1, -1, -220],
        [1, 0, 1, 1, -185],
        [2, -1, -2, -1, 181],
        [0, 1, 2, 1, -177],
        [4, 0, -2, -1, 176],
        [4, -1, -1, -1, 166],
        [1, 0, 1, -1, -164],
        [4, 0, 1, -1, 132],
        [1, 0, -1, -1, -119],
        [4, -1, 0, -1, 115],
        [2, -2, 0, 1, 107],
    ]
}
