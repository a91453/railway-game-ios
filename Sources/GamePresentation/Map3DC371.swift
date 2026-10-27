import Foundation

/// C371 standard six-car static study. Metres follow TRSC dimensions; small fittings are proportional estimates.
public enum Map3DC371 {
    public enum Unit: String, CaseIterable, Sendable { case dm, t, m, rear }
    public static let arrangement: [Unit] = [.dm,.t,.m,.m,.t,.rear]
    public static let pitch: Float = 23.5
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        if unit == .rear {
            let first=model(.dm)
            var b=StationKitBuilder();b.add(first,at:.zero,angle:.pi)
            return .flat(named:"c371-rear",from:b.mesh)
        }
        var b=MetroStudyGeometry(cab:unit == .dm,trailer:unit == .t,curved:false,length:23.5,body:Map3DPalette.counters[2],blue:Map3DPalette.containers[1])
        b.build()
        return .flat(named:"c371-"+unit.rawValue,from:b.kit.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        for (i,u) in arrangement.enumerated() { b.add(model(u),at:Map3DPoint((2.5-Float(i))*pitch,0,0)) }
        return .flat(named:"c371-formation",from:b.mesh)
    }
}
