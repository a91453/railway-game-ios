import Foundation

extension SceneKitBuilder {
    mutating func building(_ asset: Map3DSceneKit.Asset) {
        let v=asset.variant
        switch asset.family {
        case .house:
            let floors=[2,3,4,3,2,4,4,3,2][v]
            if v==8 {
                home(x:0,z:-3,length:9,width:5.7,floors:2,variant:v)
                home(x:0,z:3,length:9,width:5.7,floors:2,variant:v+1)
            } else { home(x:0,z:0,length:8.8+Float(v%3),width:5.3+Float(v%2),floors:floors,variant:v) }
        case .apartment:
            let floors=[5,6,7,8,6,5,7,6,5][v]
            home(x:0,z:0,length:15+Float(v%3)*2,width:12,floors:floors,variant:v+10)
            if v==2 || v==8 { home(x:-9,z:10,length:9,width:8,floors:floors-1,variant:v+13) }
        case .tower:
            let floors=[12,16,20,10,12,14,8,18,12][v]
            let length: Float=v==2 ? 10 : 15, width: Float=v==2 ? 10 : 13
            box(0,0,0,length+5,width+5,0.45,Map3DPalette.plaza)
            if v==8 { commercialBlock(x:0,z:0,length:24,width:19,floors:2,variant:v) }
            home(x:0,z:0,length:length,width:width,floors:floors,variant:v+20,base:v==8 ? 6.4 : 0.45)
            if v==3 || v==4 { home(x:-18,z:13,length:13,width:12,floors:floors-1,variant:v+23) }
            if v==5 {
                for level in 0..<3 {
                    box(10-Float(level)*2,Float(level)*6+0.45,0,8-Float(level),12,6,Map3DPalette.houseWalls[v].color)
                    // Put each planter on the exposed terrace, beyond the
                    // storey above. The old centres were inside that storey,
                    // leaving just foliage emerging through a vertical wall.
                    let terraceX: Float=[12.7,10.2,8.25][level]
                    planter(terraceX,Float(level+1)*6+0.45,3,size:level==2 ? 0.7 : 1.6)
                }
            }
        case .traditional: traditional(v)
        case .retail: shop(v,food:false)
        case .food: shop(v,food:true)
        case .office:
            let floors=[8,12,4,3,6,10,4,2,11][v]
            let length: Float=[18,14,27,30,18,20,16,14,17][v]
            let width: Float=[14,12,22,20,14,15,12,12,13][v]
            if v==8 { commercialBlock(x:0,z:0,length:29,width:25,floors:2,variant:v) }
            commercialBlock(x:0,z:0,length:length,width:width,floors:floors,variant:v,base:v==8 ? 6.4 : 0)
            if v==4 || v==5 || v==7 {
                box(length/2+3,3.5,0,6,width*0.65,0.22,Map3DPalette.roof)
                for z: Float in [-width*0.28,width*0.28] { box(length/2+5.5,0,z,0.25,0.25,3.5,Self.ink) }
            }
        case .civic: civic(v)
        case .industrial: industrial(v)
        default: break
        }
    }

    mutating func home(x: Float,z: Float,length: Float,width: Float,floors: Int,variant: Int,base: Float = 0) {
        let wall=Map3DPalette.houseWalls[variant%Map3DPalette.houseWalls.count].color
        let floorHeight: Float=3.1
        box(x,base,z,length+0.8,width+0.8,0.25,Map3DPalette.concrete)
        // A real arcade: the ground storey's front is recessed, with columns
        // under the upper floors, rather than dark rectangles on solid walls.
        let arcade=variant%3==0
        let groundX=x-(arcade ? 1 : 0),groundLength=length-(arcade ? 2 : 0)
        box(groundX,base+0.25,z,groundLength,width,floorHeight,wall)
        windows(x:groundX,z:z,length:groundLength,width:width,floors:1,start:base+0.25)
        if arcade {
            for i in 0...max(2,Int(width/3)) {
                let dz = -width/2+Float(i)*width/Float(max(2,Int(width/3)))
                box(x+length/2-0.2,base+0.25,z+dz,0.35,0.35,3.1,wall)
            }
        }
        for floor in 1..<floors {
            let y=base+0.25+Float(floor)*floorHeight
            box(x,y,z,length,width,floorHeight,wall)
            box(x,y,z,length+0.12,width+0.12,0.12,Map3DPalette.tileWhite)
            windows(x:x,z:z,length:length,width:width,floors:1,start:y)
            if variant%2==0 {
                let face=x+length/2,front=face+0.4,balconyWidth=width*0.78
                // Cantilever slab overlaps the structural floor by 25 cm.
                box(front,y-0.12,z,1.3,balconyWidth,0.28,Map3DPalette.concrete)
                for dz: Float in [-balconyWidth*0.36,balconyWidth*0.36] {
                    beam(Map3DPoint(face-0.08,y-0.65,z+dz),Map3DPoint(face+0.85,y-0.1,z+dz),thickness:0.14,color:Map3DPalette.concrete)
                }
                // A full-height glazed door reaches the balcony, rather than
                // a window sill with no access to the external floor.
                box(face,y+0.16,z,0.08,1.2,2.35,Map3DPalette.tileWhite)
                mesh.addFacet([Map3DPoint(face+0.047,y+0.24,z-0.49),Map3DPoint(face+0.047,y+2.37,z-0.49),
                               Map3DPoint(face+0.047,y+2.37,z+0.49),Map3DPoint(face+0.047,y+0.24,z+0.49)],color:Self.glass)
                box(front+0.59,y+0.16,z,0.09,balconyWidth,1.05,Map3DPalette.stone)
                for dz: Float in [-balconyWidth/2,balconyWidth/2] { box(front,y+0.16,z+dz,1.3,0.09,1.05,Map3DPalette.stone) }
            }
        }
        let roof=base+0.25+Float(floors)*floorHeight
        box(x,roof,z,length+0.25,width+0.25,0.2,Map3DPalette.roof)
        for sign: Float in [-1,1] {
            box(x+sign*length/2,roof+0.2,z,0.15,width,0.55,wall)
            box(x,roof+0.2,z+sign*width/2,length,0.15,0.55,wall)
        }
        box(x-length*0.23,roof+0.2,z+width*0.16,2.4,2.2,2.3,wall)
        tank(x-length*0.24,roof+2.5,z+width*0.16,blue:variant%4==2)
        if variant%5==4 { gable(x,roof+0.4,z,length:length*0.8,width:width*0.8,rise:1.1,color:Map3DPalette.tinRoofs[variant%5]) }
        // Small AC units on the side, offset from the window bays.
        for floor in 0..<min(floors,7) {
            let y=base+1+Float(floor)*floorHeight,side=z-width/2
            for dx: Float in [-0.3,0.3] {
                beam(Map3DPoint(x-length*0.28+dx,y-0.25,side+0.03),Map3DPoint(x-length*0.28+dx,y,side-0.42),thickness:0.07,color:Self.steel)
            }
            box(x-length*0.28,y,side-0.19,0.85,0.4,0.6,Map3DPalette.acUnit)
        }
    }

    mutating func traditional(_ v: Int) {
        let brick=Map3DPalette.brick,white=Map3DPalette.schoolWalls
        if v==1 || v==6 {
            for z: Float in [-7,7] {
                box(0,0,z,18,4.6,4.2,brick)
                gable(0,4.2,z,length:18,width:4.6,rise:1.8,color:Map3DPalette.roof)
            }
            box(-7,0,0,4,10,4.2,brick)
            gable(-7,4.2,0,length:4,width:10,rise:2,color:Map3DPalette.roof)
            box(0,0,0,18,18,0.15,Map3DPalette.forecourt)
            return
        }
        let length: Float=v==0 ? 14 : 9, width: Float=v==0 ? 8 : 6
        let floors=v==0 || v==4 || v==7 ? 1 : 2
        for offset in 0..<(v==8 ? 3 : 1) {
            let z=Float(offset)*6.2
            let wall=v==4 || v==7 ? white : brick
            box(0,0,z,length,width,Float(floors)*3.2,wall)
            windows(z:z,length:length,width:width,floors:floors)
            if v==5 { hip(0,6.4,z,length:length,width:width,rise:2,color:Map3DPalette.tinRoofs[2]) }
            else { gable(0,Float(floors)*3.2,z,length:length,width:width,rise:1.8,color:v==4 ? Map3DPalette.gymGreen : Map3DPalette.templeRoof) }
            if v==2 || v==8 {
                box(length/2,6.4,z,0.28,width+0.3,1.1,white)
                for dz: Float in [-width*0.35,0,width*0.35] { box(length/2,7.5,z+dz,0.4,0.4,0.35,white) }
            }
        }
    }

    mutating func shop(_ v: Int,food: Bool) {
        if food && (v==5 || v==8) {
            let width: Float=v==5 ? 18 : 14
            box(0,0,0,16,width,0.2,Map3DPalette.platform)
            for x: Float in [-6,6] { for z: Float in [-width/2+1,width/2-1] { box(x,0.2,z,0.3,0.3,4.2,Self.ink) }}
            if v==5 { mesh.addBarrelRoof(base:Map3DPoint(0,4.4,0),forward:Self.forward,length:16,width:width,rise:2,color:Map3DPalette.gymGreen,end:Map3DPalette.gymGreen) }
            else { hip(0,4.4,0,length:16,width:width,rise:2,color:Map3DPalette.gymGreen) }
            for i in -1...1 { box(2,0.2,Float(i)*4,4,3,1,Map3DPalette.counters[(i+3)%3]) }
            return
        }
        if food && v==6 {
            box(0,0.55,0,3,1.8,1.1,Self.steel)
            for x: Float in [-1.1,1.1] { wheel(x,0.4,0.75,radius:0.35,width:0.12) }
            for x: Float in [-1.4,1.4] { for z: Float in [-0.8,0.8] { box(x,1.6,z,0.05,0.05,1.1,Self.steel) }}
            gable(0,2.8,0,length:3.5,width:2.2,rise:0.5,color:Map3DPalette.shopAwnings[1])
            return
        }
        let floors=(v==1 || v==2 || v==8 || food && v==3) ? 2 : food && v==7 ? 3 : 1
        let length: Float=v==0 ? 7 : 8.5,width: Float=v==1 ? 10 : 7.5
        commercialBlock(x:0,z:0,length:length,width:width,floors:floors,variant:v)
        let front=length/2+0.8,awning=Map3DPalette.shopAwnings[v%Map3DPalette.shopAwnings.count]
        box(front,2.8,0,2,width+0.3,0.16,awning)
        box(front+0.95,2.45,0,0.08,width+0.3,0.4,awning)
        if food || v==1 {
            for z: Float in [-2,0,2] {
                box(front,0,z,1.2,1.5,0.9,Map3DPalette.counters[v%3])
                cylinder(front,0.9,z,radius:0.4,height:0.2,color:Map3DPalette.crates[(v+1)%6],sides:8)
            }
        }
        if v==6 { for z: Float in [-2.5,0,2.5] { planter(front+0.8,0,z,size:1.2) } }
        if !food && v==3 {
            for z: Float in [-2,0,2] {
                wheel(front+0.5,0.4,z-0.65,radius:0.4,width:0.1)
                wheel(front+0.5,0.4,z+0.65,radius:0.4,width:0.1)
                beam(Map3DPoint(front+0.5,0.4,z-0.65),Map3DPoint(front+0.5,1.0,z),thickness:0.07,color:Self.ink)
            }
        }
        if !food && v==5 { for z: Float in [-2,0,2] { wheel(front-1,1,z,radius:0.65,width:0.12) } }
        if food && v==3 { bench(0,Float(floors)*3.2+0.2,0) }
    }

    mutating func commercialBlock(x: Float,z: Float,length: Float,width: Float,floors: Int,variant: Int,base: Float = 0) {
        let wall=Map3DPalette.officeWalls[variant%Map3DPalette.officeWalls.count]
        box(x,base,z,length+0.6,width+0.6,0.25,Map3DPalette.plaza)
        box(x,base+0.25,z,length,width,Float(floors)*3.2,wall)
        windows(x:x,z:z,length:length,width:width,floors:floors,start:base+0.25,office:true)
        for floor in 0...floors {
            box(x,base+0.25+Float(floor)*3.2,z,length+0.08,width+0.08,0.13,Map3DPalette.tileWhite)
        }
        let roof=base+Float(floors)*3.2+0.38
        box(x-length*0.2,roof,z,3.5,3,2.4,Map3DPalette.concreteWalls[variant%3])
        for i in 0..<2 { box(x+length*0.23,roof,z+Float(i)*2.1-width*0.2,1.5,1.4,1.1,Map3DPalette.plant) }
        // Signage is a blank recessed fascia, never the reference's branding.
        box(x+length/2+0.1,base+2.4,z,0.15,width*0.85,0.6,Map3DPalette.shopAwnings[variant%4])
    }

    mutating func civic(_ v: Int) {
        if v==7 {
            box(0,0,0,24,17,6,Map3DPalette.schoolWalls)
            mesh.addBarrelRoof(base:Map3DPoint(0,6,0),forward:Self.forward,length:24,width:17,rise:3,color:Map3DPalette.gymGreen,end:Map3DPalette.glazing)
            windows(length:24,width:17,floors:1)
            return
        }
        let floors=[3,2,2,3,2,2,2,1,3][v]
        let length: Float=v==0 ? 29 : v==2 ? 20 : 18, width: Float=v==0 ? 10 : 14
        commercialBlock(x:0,z:0,length:length,width:width,floors:floors,variant:v)
        if v==0 {
            box(length/2+1.5,3.2,0,3,width+0.6,0.2,Map3DPalette.roof)
            for z: Float in [-6,-3,0,3,6] { box(length/2+2.8,0,z,0.3,0.3,3.2,Map3DPalette.schoolWalls) }
        }
        if v==2 {
            for z: Float in [-3.5,3.5] {
                box(length/2+0.04,0.3,z,0.12,4.2,3.3,Map3DTrainStyle.glass)
                box(length/2-1,0.3,z,5,2.4,2.6,Map3DPalette.lantern)
                box(length/2+1,2.1,z,1.3,2.3,0.7,Map3DPalette.glazing)
            }
            box(-length/2+1,0,width/2+1,3,3,14,Map3DPalette.stone)
        }
        if v==3 { beam(Map3DPoint(0,9.9,0),Map3DPoint(0,14,0),thickness:0.12,color:Self.steel) }
        if v==4 { box(0,6.9,0,7,5,0.15,Self.glass) }
        if v==6 { box(-length/2-2,2.6,0,4,10,0.2,Map3DPalette.gymGreen) }
    }

    mutating func industrial(_ v: Int) {
        let length: Float=20+Float(v%3)*3,width: Float=14+Float(v%2)*4
        box(0,0,0,length+4,width+4,0.2,Map3DPalette.concrete)
        if v==5 {
            for z: Float in [-4,0,4] { box(-4,0.2,z,6,3,2.5,Map3DPalette.containers[(v+Int(z+4))%4]) }
            box(length/2-1,0.2,0,4,6,3,Map3DPalette.stone)
            return
        }
        if v==7 {
            for x: Float in [-5,5] {
                box(x,0.2,0,3,4,2,Self.steel)
                for z: Float in [-1.4,1.4] { cylinder(x,2.2,z,radius:0.25,height:2.2,color:Map3DPalette.tankWhite,sides:6) }
                beam(Map3DPoint(x,4.4,-1.4),Map3DPoint(x,4.4,1.4),thickness:0.12,color:Self.steel)
            }
            return
        }
        let color=Map3DPalette.shedWalls[v%Map3DPalette.shedWalls.count]
        box(0,0.2,0,length,width,6,color)
        if v==0 {
            mesh.addSawtoothRoof(base:Map3DPoint(0,6.2,0),forward:Self.forward,length:length,width:width,teeth:4,rise:2,color:Map3DPalette.tinRoofs[0],glazing:Self.glass)
        } else if v==3 || v==6 { gable(0,6.2,0,length:length,width:width,rise:2.5,color:Map3DPalette.tinRoofs[v%5]) }
        else { box(0,6.2,0,length+0.5,width+0.5,0.18,Map3DPalette.roof) }
        for z: Float in [-width*0.25,width*0.25] {
            box(length/2+0.04,0.2,z,0.12,3.8,4,Map3DPalette.rollerDoor)
            box(length/2+1.5,0.2,z,3,4,0.9,Map3DPalette.stone)
        }
        if v==2 || v==6 { box(length/2+3,4.5,0,6,width+1,0.18,Map3DPalette.tinRoofs[1]) }
        if v==3 { for x: Float in [-6,0,6] { cylinder(x,6.2,0,radius:0.7,height:1.1,color:Self.steel) } }
        if v==4 { for x: Float in [-6,0,6] { box(x,6.4,0,2,2,1.2,Map3DPalette.acUnit) } }
        if v==8 {
            for z: Float in [-4,4] {
                cylinder(length/2+2,0.2,z,radius:0.75,height:2.5,color:Map3DPalette.tankBlue)
                beam(Map3DPoint(length/2+2,1.2,z),Map3DPoint(length/2+6,1.2,z),thickness:0.6,color:Map3DPalette.tankBlue)
            }
        }
    }
}
