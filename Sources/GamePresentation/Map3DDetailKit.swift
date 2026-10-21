import Foundation

/// Optional presentation assets. No game state, map placement, or train physics.
/// Public models and metadata use x front / y left / z up in metres.
public enum Map3DDetailKit {
    public enum Mount: String, Sendable { case ground, wall, roof, ceiling, rail }
    public struct Connector: Sendable {
        public let name: String
        public let position: Map3DPoint
        public let normal: Map3DPoint
    }
    public struct Joint: Sendable {
        public enum Kind: String, Sendable { case rotation, translation }
        public let kind: Kind
        public let pivot: Map3DPoint
        public let axis: Map3DPoint
        /// Radians for rotations; metres for translations. Pose 0 is rest.
        public let limit: ClosedRange<Float>
        public var unit: String { kind == .rotation ? "radians" : "metres" }
    }
    /// Pose is clamped to the joint limits. Nonfinite input resolves to rest.
    public static func model(for part: Part,pose: Float = 0) -> Map3DModelPack.Model {
        var fixed=StationKitBuilder(),moving=StationKitBuilder()
        fixed.detail(part,moving:&moving)
        if let joint=part.joint {
            fixed.detailAdd(.flat(named:part.id+"-moving",from:moving.mesh),joint:joint,pose:pose)
        }
        return .flat(named:part.id,from:fixed.mesh)
    }
    /// A renderer can transform only the moving body using Part.joint.
    public static func components(for part: Part) -> (fixed: Map3DModelPack.Model,moving: Map3DModelPack.Model?) {
        var fixed=StationKitBuilder(),moving=StationKitBuilder()
        fixed.detail(part,moving:&moving)
        return (.flat(named:part.id+"-fixed",from:fixed.mesh),part.joint == nil ? nil : .flat(named:part.id+"-moving",from:moving.mesh))
    }
}

extension Map3DDetailKit.Part {
    public var joint: Map3DDetailKit.Joint? {
        typealias J=Map3DDetailKit.Joint
        switch self {
        case .hingedDoor,.foldingGate: return J(kind:.rotation,pivot:Map3DPoint(0.10,0,0),axis:Map3DPoint(0,0,1),limit:0...(.pi/2))
        case .cabinetDoor: return J(kind:.rotation,pivot:Map3DPoint(0.18,0,0.12),axis:Map3DPoint(0,0,1),limit:0...(.pi/2))
        case .gateFlap: return J(kind:.rotation,pivot:Map3DPoint(0,0,0.7),axis:Map3DPoint(0,0,1),limit:0...(.pi/2))
        case .wheelset: return J(kind:.rotation,pivot:Map3DPoint(0,0,0.46),axis:Map3DPoint(0,1,0),limit:0...(2 * .pi))
        case .ventFan: return J(kind:.rotation,pivot:Map3DPoint(0.18,0,0.6),axis:Map3DPoint(1,0,0),limit:0...(2 * .pi))
        case .barrierArm: return J(kind:.rotation,pivot:Map3DPoint(0,0,0.9),axis:Map3DPoint(0,1,0),limit:0...(.pi/2))
        case .trolleyCaster: return J(kind:.rotation,pivot:Map3DPoint(0,0,0.16),axis:Map3DPoint(0,1,0),limit:0...(2 * .pi))
        case .roofHatch: return J(kind:.rotation,pivot:Map3DPoint(-0.5,0,0.14),axis:Map3DPoint(0,-1,0),limit:0...(.pi/2))
        case .serviceWindow: return J(kind:.rotation,pivot:Map3DPoint(0.12,0,1.2),axis:Map3DPoint(0,-1,0),limit:0...(.pi/3))
        case .slidingDoor,.platformDoorLeaf: return J(kind:.translation,pivot:.zero,axis:Map3DPoint(0,-1,0),limit:0...1.1)
        case .shutterSlat: return J(kind:.translation,pivot:.zero,axis:Map3DPoint(0,0,1),limit:0...0.15)
        case .connectingRod: return J(kind:.translation,pivot:.zero,axis:Map3DPoint(1,0,0),limit:0...0.6)
        case .turnoutBlade: return J(kind:.translation,pivot:.zero,axis:Map3DPoint(0,-1,0),limit:0...0.12)
        case .escalatorStep: return J(kind:.translation,pivot:.zero,axis:Map3DPoint(0.8,0,0.6),limit:0...0.4)
        default: return nil
        }
    }
    public var connectors: [Map3DDetailKit.Connector] {
        typealias C=Map3DDetailKit.Connector
        let n: Map3DPoint = mount == .wall ? Map3DPoint(-1,0,0) : mount == .ceiling ? Map3DPoint(0,0,1) : Map3DPoint(0,0,-1)
        var c=[C(name:"mount",position:.zero,normal:n)]
        switch self {
        case .wallPipeStraight:
            c += [C(name:"pipe-in",position:Map3DPoint(0.12,0,0),normal:Map3DPoint(0,0,-1)),C(name:"pipe-out",position:Map3DPoint(0.12,0,2),normal:Map3DPoint(0,0,1))]
        case .wallPipeElbow:
            c += [C(name:"pipe-in",position:Map3DPoint(0.12,0,0),normal:Map3DPoint(0,0,-1)),C(name:"pipe-out",position:Map3DPoint(0.12,-0.8,0.8),normal:Map3DPoint(0,-1,0))]
        case .wallPipeTee:
            c += [C(name:"pipe-in",position:Map3DPoint(0.12,0,0),normal:Map3DPoint(0,0,-1)),C(name:"pipe-out",position:Map3DPoint(0.12,0,2),normal:Map3DPoint(0,0,1)),C(name:"branch",position:Map3DPoint(0.12,-0.8,1),normal:Map3DPoint(0,-1,0))]
        case .cableTrough,.maintenanceWalkway,.trackDrain,.guardRail,.curbStraight:
            c += [C(name:"start",position:Map3DPoint(-1,0,0),normal:Map3DPoint(-1,0,0)),C(name:"end",position:Map3DPoint(1,0,0),normal:Map3DPoint(1,0,0))]
        default: break
        }
        if let j=joint { c.append(C(name:"axis",position:j.pivot,normal:j.axis)) }
        return c
    }
}

extension Map3DModelPack {
    public init(detailKit parts: [Map3DDetailKit.Part],includeStandard: Bool = false) {
        models=(includeStandard ? Self.standard.models : [])+parts.map { Map3DDetailKit.model(for:$0) }
    }
}

extension StationKitBuilder {
    mutating func detailAdd(_ model: Map3DModelPack.Model,joint: Map3DDetailKit.Joint,pose: Float) {
        let value=pose.isFinite ? min(joint.limit.upperBound,max(joint.limit.lowerBound,pose)) : 0
        let axis=joint.axis,c=cosf(value),s=sinf(value)
        for i in stride(from:0,to:model.vertices.count,by:3) {
            mesh.appendTriangle(model.vertices[i..<i+3].map { v in
                let p=Map3DPoint(v.x,v.y,v.z),q=p-joint.pivot
                let transformed=joint.kind == .translation ? p+axis*value : joint.pivot+q*c+axis.cross(q)*s+axis*(axis.dot(q)*(1-c))
                return Map3DVertex(Map3DPoint(transformed.x,transformed.z,-transformed.y),normal:.zero,color:v.color,layer:v.layer)
            })
        }
    }
}
