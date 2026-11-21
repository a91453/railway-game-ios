import GameCore

// TRAIN-IDENTITY (2026-11-21, the author's report on build 143): the train's
// card showed two names at once, its performance's ("Chu-Kuang, E500
// locomotive · 120 km/h · …") and its cars' type ("General train · 320 a car
// · 4 doors"), and a player could not tell which the train was. The card,
// the train types and the fleet overview now show one name, the one the 3D
// map draws the train as; how it runs and what its cars carry are figures
// under it, each saying what it describes.

extension Train {
    /// The one name a train goes by: its type's; for a train with no type,
    /// the train its performance is (the 3D map draws it as that train,
    /// ``Map3DTrainSet/key(type:performance:)``); else the general train.
    public static func identityName(type: TrainType?, performance: TrainPerformance, in language: DisplayLanguage) -> String {
        if let type { return type.title(in: language) }
        if let preset = PerformancePreset(matching: performance), preset.code != "standard" {
            return preset.title(in: language)
        }
        return standardCarName(in: language)
    }

    public func identityName(in language: DisplayLanguage) -> String {
        Self.identityName(type: type, performance: performance, in: language)
    }

    /// What one car of `type` carries and its doors, said to be the cars'
    /// (a locomotive's coaches, an EMU's cars): "Cars: 320 a car · 4 doors",
    /// "車廂：每節 320 人 · 4 門".
    public static func carsFigureText(_ type: TrainType?, in language: DisplayLanguage) -> String {
        let perCar = type?.ratedCapacityPerCar ?? ratedCapacityPerCar
        let doors = type?.doorsPerCar ?? ServiceDwell.doorsPerCar
        return language.text("Cars: \(perCar) a car · \(doors) doors", "車廂：每節 \(perCar) 人 · \(doors) 門")
    }
}

extension TrainPerformance {
    /// How it runs, with no name (the train's name is its title):
    /// "Top 120 km/h · accelerates 1.657 · brakes 2.6 km/h/s",
    /// "最高 120 km/h · 加速 1.657 · 減速 2.6 km/h/s".
    public func figuresText(in language: DisplayLanguage) -> String {
        let accelerates = Self.rateText(acceleration), brakes = Self.rateText(braking)
        return language.text(
            "Top \(topSpeed) km/h · accelerates \(accelerates) · brakes \(brakes) km/h/s",
            "最高 \(topSpeed) km/h · 加速 \(accelerates) · 減速 \(brakes) km/h/s"
        )
    }
}
