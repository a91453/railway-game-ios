import Foundation

extension StationKitBuilder {
    mutating func part(_ part: Map3DStationKit.Part) {
        switch part {
        case .platformStraight,.sidePlatform,.islandPlatform,.platformEnd:
            platform(length:8,width:part == .islandPlatform ? 6 : 4,height:1.2,roof:false)
            if part == .platformEnd { for z: Float in [-1.5,0,1.5] { box(3.8,1.2,z,0.08,0.08,1.0,Self.steel) };box(3.8,2.15,0,0.08,3.2,0.08,Self.steel) }
        case .platformCurve:
            for i in 0..<8 {
                let a=Float(i)*Float.pi/16,b=Float(i+1)*Float.pi/16
                let p=[Map3DPoint(cosf(a)*3,0,sinf(a)*3),Map3DPoint(cosf(b)*3,0,sinf(b)*3),Map3DPoint(cosf(b)*7,0,sinf(b)*7),Map3DPoint(cosf(a)*7,0,sinf(a)*7)]
                let up=Map3DPoint(0,1.2,0),centre=(p[0]+p[2])*0.5+up*0.5
                face(p,inside:centre,color:Map3DPalette.concrete);face(p.map { $0+up },inside:centre,color:Map3DPalette.platform)
                for k in 0..<4 { let j=(k+1)%4;face([p[k],p[j],p[j]+up,p[k]+up],inside:centre,color:Map3DPalette.concrete) }
                beam(p[2]+up,p[3]+up,0.12,Map3DPalette.platformEdge)
            }
        case .platformRamp: ramp(length:4,width:4,rise:1.2)
        case .platformStairs: stairs(0,0,0,run:3,width:3,rise:1.2)
        case .platformCanopy:
            for x: Float in [-3,3] { box(x,0,0,0.22,0.22,3.58,Self.steel) }
            canopy(0,3.2,0,length:8,width:4.5,rise:0.6,color:Map3DPalette.canopy)
        case .canopyEnd: canopy(0,0.22,0,length:2,width:4.5,rise:0.6,color:Map3DPalette.canopy)
        case .vColumn,.yColumn:
            box(0,0,0,0.7,0.7,0.15,Map3DPalette.concrete)
            let fork: Float=part == .yColumn ? 1.9 : 0.15
            box(0,0.15,0,0.22,0.22,max(0.03,fork-0.15),Self.steel)
            for z: Float in [-1.4,1.4] { beam(Map3DPoint(0,fork,0),Map3DPoint(0,3.2,z),0.18,Self.steel) }
        case .roofTruss:
            beam(Map3DPoint(-4,0,0),Map3DPoint(4,0,0),0.16,Self.steel)
            for i in 0..<8 {
                let x = -4+Float(i),y=2*(1-abs(x)/4),next=2*(1-abs(x+1)/4)
                beam(Map3DPoint(x,y,0),Map3DPoint(x+1,next,0),0.16,Self.steel)
                beam(Map3DPoint(x,0,0),Map3DPoint(x,y,0),0.10,Self.steel)
                beam(Map3DPoint(x,0,0),Map3DPoint(x+1,next,0),0.10,Self.steel)
            }
        case .overbridge:
            for x: Float in [-2.2,2.2] { for z: Float in [-6,6] { box(x,0,z,0.35,0.35,4.8,Self.steel) }}
            box(0,4.8,0,5,14,0.3,Map3DPalette.concrete)
            for x: Float in [-2.4,2.4] { box(x,5.1,0,0.12,14,1,Self.glass) }
            canopy(0,6.8,0,length:5.6,width:14.5,rise:1.0,color:Self.white)
            for x: Float in [-2.4,2.4] { for z: Float in [-6.5,6.5] { box(x,5.1,z,0.12,0.12,2.05,Self.steel) }}
        case .bridgeStairs: stairs(0,0,0,run:8,width:3,rise:4.8)
        case .escalator:
            stairs(0,0,0,run:5,width:1.5,rise:3)
            for z: Float in [-0.85,0.85] { beam(Map3DPoint(-2.5,0.75,z),Map3DPoint(2.5,3.75,z),0.26,Self.steel) }
        case .liftTower:
            box(0,0,0,3.2,3.2,0.2,Map3DPalette.concrete);box(0,0.2,0,2.8,2.8,5.8,Self.glass)
            for x: Float in [-1.4,1.4] { for z: Float in [-1.4,1.4] { box(x,0.2,z,0.14,0.14,5.8,Self.steel) }}
            for y: Float in [0.2,3,6] { box(0,y,0,3,3,0.15,Self.steel) };pane(1.45,0.3,0,1.1,2.2)
        case .fareGate,.wideGate:
            let spacing: Float=part == .wideGate ? 0.9 : 0.55
            for z: Float in [-spacing,spacing] {
                box(0,0,z,1.6,0.28,0.95,Self.steel);box(0.45,0.95,z,0.25,0.25,0.04,Map3DPalette.canopy)
                box(0,0.22,z/2,0.08,spacing,0.65,Self.glass)
            }
        case .ticketMachine,.vendingMachine,.chargingPoint:
            let vending=part == .vendingMachine
            box(0,0,0,vending ? 0.9 : 0.65,vending ? 1.2 : 0.75,vending ? 1.9 : 1.7,Self.white)
            pane(vending ? 0.46 : 0.335,0.75,0,vending ? 0.92 : 0.47,vending ? 0.9 : 0.50)
            box(vending ? 0.48 : 0.35,0.23,0,0.06,0.38,0.14,Self.ink)
            if part == .chargingPoint { beam(Map3DPoint(0.2,1.3,0.42),Map3DPoint(0.2,0.5,0.55),0.07,Self.ink) }
        case .ticketCounter:
            box(0,0,0,1.2,3.2,1.0,Self.white);box(0,1,0,1.5,3.4,0.12,Self.steel)
            for z: Float in [-1.5,0,1.5] { box(-0.4,1.1,z,0.08,0.08,1.1,Self.steel) }
            box(-0.4,1.1,0,0.05,3,1.0,Self.glass)
        case .serviceBooth,.utilityHut,.toiletBlock:
            let w: Float=part == .toiletBlock ? 6 : 3
            facade(0,0,0,3,w,2.8,Self.white,bays:part == .toiletBlock ? 3 : 1)
            hip(0,2.8,0,3.2,w+0.2,0.7,Map3DPalette.gymGreen)
            pane(1.54,0.10,-w*0.23,0.75,2.2)
        case .informationBoard,.platformSign,.exitSign,.timetableBoard,.wayfindingPylon:
            let width: Float=part == .wayfindingPylon ? 0.9 : part == .informationBoard ? 3.5 : 2.2
            box(0,0,0,0.7,width+0.3,0.12,Map3DPalette.concrete)
            for z: Float in [-width*0.35,width*0.35] { box(0,0.12,z,0.12,0.12,1.6,Self.steel) }
            box(0,1.6,0,0.22,width,part == .wayfindingPylon ? 1.7 : 1,Self.ink)
            for y: Float in [1.8,2.05,2.3] { box(0.12,y,0,0.025,width*0.75,0.06,Map3DPalette.platformEdge) }
        case .clockPole:
            box(0,0,0,0.8,0.8,0.15,Map3DPalette.concrete);cylinder(0,0.15,0,radius:0.10,height:3.3,color:Self.steel,sides:8)
            clockFace(0.08,3.25,0,size:1.1)
        case .tactileStraight,.tactileJunction:
            box(0,0,0,4,0.6,0.04,Map3DPalette.platformEdge)
            for z: Float in [-0.18,0,0.18] { box(0,0.04,z,4,0.035,0.015,Map3DPalette.platformEdge) }
            if part == .tactileJunction { box(0,0,0,0.6,4,0.04,Map3DPalette.platformEdge) }
        case .platformScreenDoors,.halfHeightScreenDoors:
            let height: Float=part == .platformScreenDoors ? 2.5 : 1.3
            for i in 0..<4 {
                let x = -3+Float(i)*2
                box(x,0,0,1.9,0.12,height,Self.glass)
                for dx: Float in [-0.95,0.95] { box(x+dx,0,0,0.08,0.18,height,Self.steel) }
                box(x,height-0.12,0,2,0.20,0.12,Map3DPalette.canopy)
            }
        case .safetyFence: fence(length:8,height:1.1)
        case .bench,.backlessBench: bench(0,0,0,back:part == .bench)
        case .waitingShelter,.bikeShelter,.busShelter,.taxiCanopy:
            let length: Float=part == .taxiCanopy ? 8 : 4
            for x: Float in [-length/2+0.2,length/2-0.2] { for z: Float in [-1.4,1.4] { box(x,0,z,0.13,0.13,2.8,Self.steel) }}
            canopy(0,2.8,0,length:length+0.5,width:3.4,rise:0.6,color:part == .bikeShelter ? Map3DPalette.gymGreen : Map3DPalette.canopy)
            if part == .waitingShelter || part == .busShelter { bench(0,0,0);box(-length/2+0.2,0.3,0,0.06,2.8,2.3,Self.glass) }
            if part == .bikeShelter { for x: Float in [-1,0,1] { bikeHoop(x,0,0) } }
        case .baggageLocker:
            box(0,0,0,0.6,3,2,Self.white)
            for i in 0..<4 { for j in 0..<3 {
                let z = -1.12+Float(i)*0.75,y=0.08+Float(j)*0.64
                box(0.31,y,z,0.04,0.68,0.57,Self.glass);box(0.34,y+0.24,z+0.2,0.03,0.05,0.12,Self.ink)
            }}
        case .drinkingFountain:
            box(0,0,0,0.65,0.9,0.8,Self.steel);box(0,0.8,0,0.8,1.0,0.13,Self.white)
            cylinder(-0.15,0.93,0,radius:0.035,height:0.17,color:Self.steel,sides:6)
        case .binPair:
            for z: Float in [-0.38,0.38] { box(0,0,z,0.55,0.58,0.85,z<0 ? Map3DPalette.canopy : Map3DPalette.gymGreen);box(0,0.85,z,0.58,0.60,0.08,Self.steel) }
        case .publicPhone:
            box(0,0,0,1.2,1.2,0.12,Map3DPalette.concrete)
            for z: Float in [-0.55,0.55] { box(-0.5,0.12,z,0.1,0.1,2.1,Self.steel) }
            box(-0.5,0.12,0,0.08,1.1,2.1,Self.glass);box(0,2.22,0,1.3,1.3,0.13,Map3DPalette.canopy)
            box(-0.3,1.0,0,0.3,0.42,0.65,Map3DPalette.gymGreen)
        case .bikeRack:
            for z: Float in [-1,0,1] { bikeHoop(0,0,z) }
        case .bollardRow:
            for z: Float in [-2,-1,0,1,2] { cylinder(0,0,z,radius:0.09,height:0.85,color:Self.steel,sides:8) }
        case .planterBench,.stationTree:
            box(0,0,0,2.8,2.8,0.40,Map3DPalette.concrete);box(0,0.40,0,2.3,2.3,0.06,Map3DPalette.park);tree(0,0.46,0,size:0.9)
            if part == .planterBench { for z: Float in [-1.55,1.55] { bench(0,0,z) } }
        case .catenaryPortal:
            for z: Float in [-4,4] { box(0,0,z,0.6,0.6,0.2,Map3DPalette.concrete);box(0,0.2,z,0.20,0.20,6,Self.steel) }
            box(0,6.2,0,0.20,8.2,0.20,Self.steel)
            for z: Float in [-2,0,2] { box(0,5.3,z,0.10,0.10,0.9,Self.steel) }
        case .bufferStop:
            track(-2,2,0)
            for z: Float in [-0.7,0.7] { beam(Map3DPoint(-1,0.2,z),Map3DPoint(1,1.4,z),0.22,Self.steel) }
            box(1,1.2,0,0.3,2,0.4,Map3DPalette.platformEdge)
        case .signalMast:
            cylinder(0,0,0,radius:0.12,height:4,color:Self.steel,sides:8);box(0,0,0,0.65,0.65,0.18,Map3DPalette.concrete)
            box(0.10,2.8,0,0.25,0.65,1.35,Self.ink)
            for (i,color) in [Map3DPalette.lantern,Map3DPalette.platformEdge,Map3DPalette.crown].enumerated() {
                let start=mesh.vertices.count;box(0.24,2.95+Float(i)*0.4,0,0.05,0.3,0.22,color);mesh.makeGlowing(from:start)
            }
        case .relayCabinet:
            box(0,0,0,0.9,1.4,0.15,Map3DPalette.concrete);box(0,0.15,0,0.75,1.2,1.4,Self.steel)
            for z: Float in [-0.25,0.25] { box(0.39,0.3,z,0.04,0.42,1.1,Self.white) }
        case .ventShaft,.smokeVent:
            box(0,0,0,2.5,2.5,0.2,Map3DPalette.concrete);box(0,0.2,0,2,2,2.8,Self.steel)
            for y in stride(from:Float(0.45),to:2.8,by:0.3) { box(1.03,y,0,0.08,1.6,0.10,Self.ink) }
            box(0,3,0,2.6,2.6,0.18,Self.white)
        case .stairHead,.undergroundExit:
            let below=part == .undergroundExit
            stairs(0,below ? -2.4 : 0,0,run:4,width:2.4,rise:2.4)
            for z: Float in [-1.5,1.5] { box(0,below ? -2.4 : 0,z,4.5,0.22,below ? 3.4 : 1.1,Map3DPalette.concrete);box(1.8,0,z,0.12,0.12,2.8,Self.steel) }
            canopy(0,2.8,0,length:5,width:3.5,rise:0.5,color:Self.glass)
            for z: Float in [-1.5,1.5] { box(-1.8,0,z,0.12,0.12,2.8,Self.steel) }
        case .stationEntrance:
            for z: Float in [-3,3] { box(0,0,z,1,0.65,4.2,Map3DPalette.schoolWalls) }
            box(0,3.3,0,1,6.5,0.7,Map3DPalette.schoolWalls)
            canopy(0,4,0,length:4,width:7.5,rise:1.1,color:Map3DPalette.gymGreen)
        case .stationRoofWing: canopy(0,0.22,0,length:6,width:8,rise:1.2,color:Self.white,wave:false)
        case .skylight:
            box(0,0,0,4,4,0.2,Self.steel);hip(0,0.2,0,3.6,3.6,1.0,Self.glass)
        case .footpathTile,.forecourtTile:
            box(0,0,0,4,4,0.20,part == .footpathTile ? Map3DPalette.concrete : Map3DPalette.plaza)
            for x: Float in [-1,0,1] { box(x,0.20,0,0.025,4,0.008,Map3DPalette.stone) }
        case .lampPole:
            box(0,0,0,0.6,0.6,0.15,Map3DPalette.concrete);cylinder(0,0.15,0,radius:0.08,height:4.1,color:Self.steel,sides:8)
            beam(Map3DPoint(0,4.25,0),Map3DPoint(0.8,4.25,0),0.10,Self.steel)
            let start=mesh.vertices.count;box(0.8,4.10,0,0.7,0.35,0.15,Map3DProp.lampLight);mesh.makeGlowing(from:start)
        case .wallPlain,.wallWindow,.wallTwinWindow,.wallDoor,.wallShopfront,.wallLouver,.wallCorner:
            wallModule(part)
        case .arcadeBay:
            box(-1.85,0,0,0.3,4,3.2,Self.white)
            for z: Float in [-1.85,1.85] { box(1.6,0,z,0.3,0.3,3.2,Self.white) }
            box(0,3.0,0,4,4,0.2,Map3DPalette.concrete);pane(-1.64,0.2,0,1.2,2.25)
        case .floorSlab,.flatRoof: box(0,0,0,4,4,0.2,Map3DPalette.concrete)
        case .balcony,.balconyCorner:
            box(-0.15,0,0,0.3,4,3.2,Self.white);pane(0.01,0.2,0,1.2,2.25)
            box(0.55,0,0,1.7,4,0.2,Map3DPalette.concrete)
            box(1.35,0.2,0,0.1,4,1.05,Map3DPalette.stone)
            for z: Float in [-1.95,1.95] { box(0.55,0.2,z,1.7,0.1,1.05,Map3DPalette.stone) }
            for z: Float in [-1.3,1.3] {
                box(-0.03,-0.8,z,0.10,0.25,1.0,Map3DPalette.concrete)
                beam(Map3DPoint(0,-0.7,z),Map3DPoint(1.2,0,z),0.14,Map3DPalette.concrete)
            }
            if part == .balconyCorner { box(-1,0,-1.85,2,0.3,3.2,Self.white);box(-0.9,0,-2.4,2.1,1.4,0.2,Map3DPalette.concrete);box(-0.9,0.2,-3.05,2.1,0.1,1.05,Map3DPalette.stone) }
        case .roofParapet:
            box(0,0,0,0.25,4,0.9,Self.white);box(0,0.9,0,0.4,4.1,0.10,Map3DPalette.stone)
        case .roofAccess:
            box(0,0,0,3,3,2.6,Self.white);pane(1.54,0.1,0,0.9,2.2);box(0,2.6,0,3.3,3.3,0.2,Map3DPalette.concrete)
        case .gableRoof: gable(0,0.12,0,4,4,1.4,Map3DPalette.gymGreen)
        case .hipRoof: hip(0,0.12,0,4,4,1.4,Map3DPalette.templeRidge)
        case .roofDrain:
            box(0,0,0,0.6,0.6,0.06,Self.steel)
            for z: Float in [-0.2,-0.1,0,0.1,0.2] { box(0,0.06,z,0.5,0.025,0.025,Self.ink) }
        case .downpipe:
            cylinder(0.12,0,0,radius:0.07,height:3.2,color:Self.steel,sides:8)
            for y: Float in [0.3,1.6,2.9] { beam(Map3DPoint(-0.02,y,0),Map3DPoint(0.12,y,0),0.10,Self.steel) }
        case .acBracket:
            for z: Float in [-0.4,0.4] { beam(Map3DPoint(-0.02,0,z),Map3DPoint(0.65,0.45,z),0.07,Self.steel);beam(Map3DPoint(-0.02,0.45,z),Map3DPoint(0.65,0.45,z),0.07,Self.steel) }
        case .acCondenser:
            for z: Float in [-0.38,0.38] { box(0,0,z,0.5,0.10,0.14,Self.steel) }
            box(0,0.14,0,0.5,1,0.65,Map3DPalette.acUnit)
            for z in stride(from:Float(-0.38),through:0.4,by:0.10) { box(0.26,0.25,z,0.03,0.025,0.4,Self.steel) }
        case .waterTank,.waterTankStand:
            for x: Float in [-0.6,0.6] { for z: Float in [-0.6,0.6] { box(x,0,z,0.10,0.10,0.5,Self.steel) }}
            box(0,0.45,0,1.5,1.5,0.1,Self.steel)
            if part == .waterTank {
                cylinder(0,0.55,0,radius:0.85,height:1.6,color:Map3DPalette.tankSteel)
                for y: Float in [0.9,1.6] { cylinder(0,y,0,radius:0.87,height:0.06,color:Self.steel) }
                cylinder(0,2.15,0,radius:0.28,height:0.1,color:Self.steel)
            }
        case .solarArray:
            for x: Float in [-1,1] { for z: Float in [-1.3,1.3] { box(x,0,z,0.10,0.10,x<0 ? 0.45 : 0.9,Self.steel) }}
            for z: Float in [-0.8,0.8] { beam(Map3DPoint(-1.2,0.45,z),Map3DPoint(1.2,0.95,z),0.15,Map3DPalette.canopy) }
            // One closed sloped panel, rather than disconnected flat steps.
            let low=[Map3DPoint(-1.2,0.45,-1.5),Map3DPoint(1.2,0.95,-1.5),Map3DPoint(1.2,0.95,1.5),Map3DPoint(-1.2,0.45,1.5)]
            let p=low+low.map { $0+Map3DPoint(0,0.12,0) },centre=Map3DPoint(0,0.76,0)
            for f in [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]] { face(f.map { p[$0] },inside:centre,color:Map3DPalette.canopy) }
        case .roofDuct:
            box(0,0,0,3.2,0.8,0.65,Self.steel);box(1.2,0.65,0,0.8,0.8,0.8,Self.steel)
        case .roofFan:
            box(0,0,0,1.3,1.3,0.15,Self.steel);cylinder(0,0.15,0,radius:0.55,height:0.7,color:Self.steel)
            cylinder(0,0.85,0,radius:0.7,height:0.15,color:Self.white)
        case .fireEscape:
            for z: Float in [-0.4,0.4] { beam(Map3DPoint(0.30,0,z),Map3DPoint(0.30,3.2,z),0.08,Self.steel) }
            for y in stride(from:Float(0.15),to:3.2,by:0.28) { beam(Map3DPoint(0.30,y,-0.4),Map3DPoint(0.30,y,0.4),0.06,Self.steel) }
            for y: Float in [0.2,1.6,3] { beam(Map3DPoint(-0.02,y,0),Map3DPoint(0.3,y,0),0.08,Self.steel) }
        case .externalStairs: stairs(0,0,0,run:5,width:2,rise:3.2)
        case .shopAwning:
            box(0.7,0.6,0,1.5,4,0.12,Map3DPalette.gymGreen);box(1.4,0.25,0,0.1,4,0.35,Map3DPalette.gymGreen)
            for z: Float in [-1.6,1.6] { beam(Map3DPoint(-0.02,0,z),Map3DPoint(1.3,0.6,z),0.08,Self.steel) }
        case .rollerShutter:
            box(0,0,0,0.2,3.5,2.6,Self.white)
            for y in stride(from:Float(0.15),to:2.4,by:0.18) { box(0.12,y,0,0.06,3.2,0.12,Self.steel) }
        case .blankSign:
            box(0.15,0,0,0.3,3,0.9,Map3DPalette.gymGreen)
            for z: Float in [-1.1,1.1] { beam(Map3DPoint(-0.02,0.3,z),Map3DPoint(0.3,0.3,z),0.08,Self.steel) }
        case .loadingBay:
            box(0,0,0,6,4,1.1,Map3DPalette.concrete);ramp(length:4,width:2,rise:1.1,offset:Map3DPoint(-4,0,0))
            for z: Float in [-1.8,1.8] { box(2.6,1.1,z,0.12,0.12,1.0,Self.steel) }
        case .fenceGate:
            fence(length:8,height:2)
            for x: Float in [-3.8,3.8] { box(x,0,0,0.4,0.4,2.3,Map3DPalette.concrete) }
        }
    }
    mutating func bikeHoop(_ x: Float,_ y: Float,_ z: Float) {
        for dx: Float in [-0.45,0.45] { box(x+dx,y,z,0.07,0.07,0.8,Self.steel) }
        beam(Map3DPoint(x-0.45,y+0.8,z),Map3DPoint(x+0.45,y+0.8,z),0.07,Self.steel)
    }
    mutating func fence(length: Float,height: Float) {
        for x in stride(from:-length/2,through:length/2,by:Float(1)) { box(x,0,0,0.07,0.07,height,Self.steel) }
        for y: Float in [height*0.3,height] { box(0,y,0,length,0.07,0.07,Self.steel) }
    }
    mutating func wallModule(_ part: Map3DStationKit.Part) {
        box(-0.15,0,0,0.3,4,3.2,Self.white)
        switch part {
        case .wallWindow: pane(0.01,0.8,0,1.8,1.5)
        case .wallTwinWindow: for z: Float in [-1,1] { pane(0.01,0.8,z,1.2,1.5) }
        case .wallDoor: pane(0.01,0.12,0,1.1,2.3)
        case .wallShopfront: pane(0.01,0.2,0,3.4,2.4)
        case .wallLouver: for y in stride(from:Float(0.5),to:2.8,by:0.25) { box(0.07,y,0,0.12,3,0.09,Self.steel) }
        case .wallCorner: box(-2,0,1.85,4,0.3,3.2,Self.white)
        default: break
        }
    }
    mutating func ramp(length: Float,width: Float,rise: Float,offset: Map3DPoint = .zero) {
        let p=[Map3DPoint(-length/2,0,-width/2),Map3DPoint(length/2,0,-width/2),Map3DPoint(length/2,0,width/2),Map3DPoint(-length/2,0,width/2),Map3DPoint(length/2,rise,-width/2),Map3DPoint(length/2,rise,width/2)].map { $0+offset }
        let c=offset+Map3DPoint(0,rise/3,0)
        for f in [[0,1,2,3],[0,3,5,4],[1,4,5,2],[0,4,1],[3,2,5]] { face(f.map { p[$0] },inside:c,color:Map3DPalette.concrete) }
        for z: Float in [-width/2,width/2] { beam(offset+Map3DPoint(-length/2,0.9,z),offset+Map3DPoint(length/2,rise+0.9,z),0.06,Self.steel) }
    }
}
