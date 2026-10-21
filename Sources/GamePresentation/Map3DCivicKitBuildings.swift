import Foundation

extension StationKitBuilder {
    mutating func civicBuilding(_ part: Map3DCivicKit.Part) {
        let white=Self.white,blue=Map3DPalette.canopy,concrete=Map3DPalette.concreteWalls[0],red=Self.civicRed,green=Self.civicGreen
        switch part {
        case .clinic:
            box(0,0,0,12,13,0.15,Map3DPalette.plaza)
            civicBlock(-1,0.15,0,length:8,width:10,floors:2,color:white)
            civicEntrance(3,0.15,0,width:2.2)
            civicBoard(3.04,4.2,0,width:2.4,height:1.4,color:blue)
            box(3.11,4.75,0,0.03,1.0,0.20,white);box(3.11,4.45,0,0.03,0.20,0.80,white)
            for z: Float in [-4,4] { cylinder(4,0.15,z,radius:0.45,height:0.32,color:Map3DPalette.trunk);tree(4,0.47,z,size:0.4) }
        case .policePost:
            box(0,0,0,12,12,0.15,Map3DPalette.plaza)
            civicBlock(-0.7,0.15,0,length:8,width:8.8,floors:2,color:concrete,roof:blue)
            box(2.2,0.15,0,2.2,9,0.30,Map3DPalette.concrete)
            for z: Float in [-3.6,3.6] { box(3,0.45,z,0.20,0.20,2.8,Self.steel) }
            box(3,3.25,0,1.8,8.2,0.20,blue);civicEntrance(3.3,0.45,0,width:2)
            civicBoard(3.34,3.55,0,width:3.6,height:0.75,color:blue)
            cylinder(3.8,0.15,-5,radius:0.045,height:5,color:Self.steel,sides:8)
        case .fireStation:
            box(0,0,0,15,15,0.15,Map3DPalette.plaza)
            civicBlock(-2,0.15,0,length:7,width:12,floors:2,color:white,roof:red)
            for z: Float in [-3,3] {
                // Actual garage apertures, with closed lintels and jambs.
                for dz: Float in [-2.4,2.4] { box(3,0.15,z+dz,3,0.22,3.4,concrete) }
                box(3,3.55,z,3,5,0.25,concrete)
                box(1.55,0.15,z,0.10,4.6,3.25,Self.ink)
                for i in 0..<10 { box(4.52,2.8+Float(i)*0.05,z,0.04,4.7,0.035,red) }
                box(4.6,0.15,z,0.6,5,0.08,Map3DPalette.platformEdge)
            }
            civicBlock(-4,0.15,5.6,length:2.6,width:2.5,floors:3,color:concrete,roof:red)
        case .postOffice:
            box(0,0,0,12,13,0.15,Map3DPalette.plaza)
            civicBlock(-1,0.15,0,length:8,width:10,floors:1,color:white,roof:green)
            civicEntrance(3,0.15,0,width:2.3)
            box(3.1,2.6,0,0.15,10.4,0.55,green)
            for z: Float in [-4,4] { box(4.4,0.15,z,0.5,0.5,1.0,green);box(4.66,0.85,z,0.025,0.32,0.06,Self.ink) }
            box(-2,3.33,0,4,7,0.18,Map3DPalette.playerRoof)
        case .primarySchool:
            box(0,0,0,22,24,0.15,Map3DPalette.plaza)
            civicBlock(-5,0.15,0,length:5,width:20,floors:2,color:Map3DPalette.playerRoof,roof:blue)
            for z: Float in [-8,8] { civicBlock(1,0.15,z,length:10,width:4,floors:2,color:white,roof:blue) }
            for z in stride(from:Float(-6),through:6,by:3) { box(-1.9,0.15,z,0.16,0.16,3,Self.steel) }
            box(-1.9,3.15,0,1.2,17,0.18,concrete)
            box(3,0.15,0,10,8,0.035,Map3DPalette.park)
            for z: Float in [-10,10] { cylinder(7,0.15,z,radius:0.3,height:0.4,color:concrete) }
        case .kindergarten:
            box(0,0,0,15,16,0.15,Map3DPalette.park)
            civicBlock(-2,0.15,0,length:7,width:11,floors:1,color:Map3DPalette.playerRoof,roof:blue)
            for z: Float in [-3.5,0,3.5] { gable(1.2,3.33,z,1.0,3.2,0.75,z==0 ? red : blue) }
            civicEntrance(1.5,0.15,0,width:1.8)
            for z: Float in [-4.5,-1.5,1.5,4.5] { box(5,0.15,z,0.08,0.08,0.9,blue) }
            for y: Float in [0.40,0.80] { box(5,y,0,0.08,10,0.08,Map3DPalette.player) }
            box(3.7,0.15,4.5,2,1.2,0.25,Map3DPalette.platformEdge)
        case .library:
            box(0,0,0,16,18,0.15,Map3DPalette.plaza)
            civicBlock(-1.2,0.15,0,length:10,width:13,floors:2,color:concrete)
            civicBlock(-2,6.33,0,length:7,width:9,floors:1,color:white,roof:blue)
            civicEntrance(3.8,0.15,0,width:2.5)
            for z in stride(from:Float(-5.5),through:5.5,by:1.1) { box(3.95,3.6,z,0.25,0.07,2.0,Self.steel) }
            box(5.2,0.15,0,2.8,7,0.18,concrete)
            for z: Float in [-6,6] { bench(5,0.15,z) }
        case .communityHall:
            box(0,0,0,16,18,0.15,Map3DPalette.plaza)
            civicBlock(-1,0.15,0,length:10,width:12,floors:1,color:Map3DPalette.playerRoof)
            gable(-1,3.33,0,10,12,1.6,blue)
            civicEntrance(4,0.15,0,width:3.5)
            for z: Float in [-5,-2.5,2.5,5] { box(5.5,0.15,z,0.16,0.16,2.75,Self.steel) }
            box(4.8,2.9,0,2.0,13,0.15,blue)
        case .schoolGym:
            box(0,0,0,20,24,0.15,Map3DPalette.plaza)
            box(0,0.15,0,15,18,5,concrete)
            civicWindowBands(0,2.0,0,length:15,width:18,floors:1,bays:6)
            canopy(0,5.15,0,length:15.5,width:19,rise:2,color:blue)
            for z: Float in [-8.5,8.5] { for x: Float in [-6,-3,0,3,6] { box(x,0.15,z,0.20,0.20,5,Self.steel) } }
            civicEntrance(7.5,0.15,0,width:3)
            box(0,0.15,0,12,15,0.025,Self.civicWood)
        case .dayCareCenter:
            box(0,0,0,16,18,0.15,Map3DPalette.park)
            civicBlock(-2,0.15,0,length:8,width:12,floors:1,color:white,roof:green)
            civicBlock(1,0.15,-4,length:6,width:4,floors:1,color:Map3DPalette.playerRoof,roof:green)
            civicEntrance(2,0.15,2,width:2)
            for z: Float in [1,3,5] { bench(5,0.15,z) }
            tree(5,0.15,-4,size:0.7)
        case .publicToilet:
            box(0,0,0,10,12,0.15,Map3DPalette.plaza)
            box(-0.8,0.15,0,5.8,8.5,2.9,concrete)
            for z: Float in [-2.8,0,2.8] { pane(2.15,0.15,z,1.25,2.2) }
            for z: Float in [-3.5,-1.8,1.8,3.5] { box(2.112,2.35,z,0.04,0.6,0.22,Self.glass) }
            box(0,3.05,0,8,9.5,0.18,green)
            for z: Float in [-4,4] { box(3.5,0.15,z,0.16,0.16,2.9,Self.steel) }
        case .marketHall:
            box(0,0,0,20,22,0.15,Map3DPalette.plaza)
            box(-2,0.15,0,11,17,3.2,concrete)
            gable(-2,3.35,0,11,17,1.7,blue)
            for z: Float in [-6,-2,2,6] { pane(3.55,0.15,z,2.8,2.6) }
            for z: Float in [-8,-4,0,4,8] { box(6.2,0.15,z,0.16,0.16,2.8,Self.steel) }
            box(4.7,2.95,0,3.8,18.5,0.16,Map3DPalette.playerRoof)
        default: break
        }
    }
}
