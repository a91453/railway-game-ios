import Foundation

/// C381 standard six-car static study; cab is 23.710 m between coupling faces.
public enum Map3DC381 {
    public enum Unit: String, CaseIterable, Sendable { case dm, t, m, rear }
    public static let arrangement: [Unit] = [.dm,.t,.m,.m,.t,.rear]
    public static let lengths: [Float] = [23.710,23.5,23.5,23.5,23.5,23.710]
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        if unit == .rear {
            let first=model(.dm)
            var b=StationKitBuilder();b.add(first,at:.zero,angle:.pi)
            return .flat(named:"c381-rear",from:b.mesh)
        }
        var b=MetroStudyGeometry(cab:unit == .dm,trailer:unit == .t,curved:true,length:unit == .dm ? 23.710 : 23.5,body:Map3DPalette.shopAwnings[3],blue:Map3DPalette.containers[1])
        b.build()
        return .flat(named:"c381-"+unit.rawValue,from:b.kit.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        let centres: [Float] = [58.855,35.25,11.75,-11.75,-35.25,-58.855]
        for (i,u) in arrangement.enumerated() { b.add(model(u),at:Map3DPoint(centres[i],0,0)) }
        return .flat(named:"c381-formation",from:b.mesh)
    }
}
