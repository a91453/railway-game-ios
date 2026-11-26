// SPLIT-HOTSPOTS-2 (REAL-TRAINS-PER-REGION): which of the game's train
// sets Taiwan's real lines run (the High Speed Rail, the Taiwan Railway,
// the metros, the light rails and the Alishan Forest Railway), split from
// Map3DRealTrains.swift's ``Map3DRealTrains/formation(system:id:name:)``,
// with the Taiwan Railway's trains by model, so that a pull request
// adding one place's trains changes only its file.

extension Map3DRealTrains {
    /// The part of ``formation(system:id:name:)`` for Taiwan's systems;
    /// `nil` for a system of another place.
    static func taiwanFormation(system: String, id: String, name: String) -> Formation? {
        switch system {
        case "thsr":
            // The 700T: twelve cars.
            return Formation(key: "highSpeed", cars: 12)
        case "tra":
            // The diesel branches' DR1000 railcars, three on a weekday;
            // the rest the EMU800, eight cars, as most local trains
            // (`dr1000`, `commuter`).
            if Map3DScene.dieselBranches.contains(where: { name.hasPrefix($0) }) { return Formation(key: "dieselRailcar", cars: 3) }
            return Formation(key: "emu800", cars: 8)
        case "trtc":
            // Decision 461: each line's own fleet, of the models the game
            // has (the C301 and C321 have none: the line's other fleet
            // stands in for them).
            switch id {
            // Decision 558: the Wenhu line's four cars, two pairs of its
            // 370 or, a third of its trains, its VAL256
            // (``Map3DTrainSet/wenhuLine(number:)``).
            case "BR": return Formation(key: Map3DTrainSet.wenhu370Key, cars: 4)
            // The Circular line's four-car 610.
            case "Y": return Formation(key: "circular610", cars: 4)
            // The branch shuttles' three-car C371s.
            case "R_XBT", "G_XBT": return Formation(key: "metroC371", cars: 3)
            // The Bannan line's C321 and C341: the C341.
            case "BL": return Formation(key: "metroC341", cars: 6)
            // The Tamsui-Xinyi line's C301 and C381: the C381.
            case "R": return Formation(key: "metroC381", cars: 6)
            // The Songshan-Xindian line's C371 and C381: half each.
            case "G": return Formation(key: "metroC381", cars: 6, alternate: "metroC371")
            // The Zhonghe-Xinlu line's (both branches) C371.
            default: return Formation(key: "metroC371", cars: 6)
            }
        case "krtc":
            // Decision 461: the other cities' metros are not Taipei's.
            // Decision 496: the Circular light rail's CAF and Citadis
            // trains, by their number (``Map3DTrainSet/kaohsiungLightRail(number:)``).
            if id == "C" { return Formation(key: "klrtCitadis", cars: 2) }
            // Decision 483: the Red and Orange lines' Siemens three cars.
            return Formation(key: "kaohsiung", cars: 3)
        case "tymc":
            // Decision 561: the commuter train's four cars, its 1000; an
            // express trip's train the 2000's five
            // (``formation(of:system:place:locked:)``).
            return Formation(key: Map3DTrainSet.taoyuanAirport1000Key, cars: 4)
        case "tmrt":
            // Decision 483: the Green line's own two cars.
            return Formation(key: "taichungGreen", cars: 2)
        case "sanying":
            // Decision 466: its own two-car train.
            return Formation(key: Map3DTrainSet.sanyingKey, cars: 2)
        case "ntdlrt":
            // Decision 496: the light rail's own five modules, about 34 m,
            // as two cars (decision 331's green tram before).
            return Formation(key: "danhaiLRT", cars: 2)
        case "ntalrt":
            return Formation(key: "ankengLRT", cars: 2)
        case "afr":
            // Decision 531: the Alishan Forest Railway's locomotive and five
            // coaches (`integration/formations.js` `forest`, estimated from
            // the forest railway's charter information), the DL-38 and its
            // coaches at their own lengths, about 74 m.
            return Formation(key: "ALISHAN", cars: 6)
        default:
            return nil
        }
    }

    /// Decision 511: the DR3100 diesel express, three cars, one set as
    /// it runs (`integration/formations.js` `dr3100`: fixed sets of three,
    /// the timetable does not say how many coupled).
    static let dr3100 = Formation(key: "dieselExpress", cars: 3)

    /// Decision 532: the formation a Taiwan Railway train of `model` (its
    /// timetable's `carName`) is drawn as, `rail-3d`'s
    /// `integration/formations.js` `baseFormation`: the EMU3000's twelve
    /// cars (and the 110K and 110M, as it has them), the Taroko's and the
    /// Puyuma's eight, the push-pull's twelve coaches and a power car at
    /// each end, decision 511's DR3100, and a Chu-Kuang's locomotive and
    /// eight coaches; `nil` for any other (a local train), which runs as
    /// its line's.
    static func traFormation(model: String) -> Formation? {
        if model.hasPrefix("自強(3000") || model == "110K" || model == "110M" { return Formation(key: "emu3000", cars: 12) }
        if model.contains("(太,") { return Formation(key: "taroko", cars: 8) }
        if model.contains("(普,") { return Formation(key: "puyuma", cars: 8) }
        if model.contains("(PP") { return Formation(key: "pushPull", cars: 14) }
        if model.contains("(D31") { return dr3100 }
        if model.contains("莒光") || model.contains("普通車") { return Formation(key: "E200CK", cars: 9) }
        return nil
    }
}
