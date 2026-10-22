import Foundation
import GameCore

// Decision 239: a real-world map's real buildings round Kaohsiung and
// Taichung Stations, from the 3D city preview's tiles (``CityTileArea``):
// each footprint raised to its height in the 3D map's own look, the colours
// and roof clutter of decision 235, by what the building is used for.

extension Map3DScene.Builder {
    /// What a real building is drawn as, by its usage code
    /// (`Web/CityView/tools/pipeline/taiwan.mjs`, `usageOf`).
    enum RealKind: Equatable {
        /// 413: a 透天厝 street's shophouse, shops under homes.
        case shophouse
        /// 414: a block of flats.
        case flats
        /// 401, 404: offices, hotels and shops.
        case office
        /// 441: works and warehouses.
        case industry
        /// 421, 422: schools, hospitals, offices of the state.
        case civic
        /// 454: temples.
        case temple
        /// 431: stations, car parks.
        case transport

        init(usage: Int) {
            switch usage {
            case 401...404: self = .office
            case 414: self = .flats
            case 421, 422: self = .civic
            case 431: self = .transport
            case 441: self = .industry
            case 454: self = .temple
            default: self = .shophouse
            }
        }
    }

    /// The real buildings of `areas` in the scene, laid on the world by
    /// `frame`, but those standing on cells the track runs through.
    /// Returns the 64 m cells they stand on, which keep no city lot.
    @discardableResult
    mutating func addRealBuildings(_ areas: [CityTileArea], frame: RealWorldFrame, clearOf cleared: Set<Map3DScene.ChunkKey>)
        -> Set<Map3DScene.ChunkKey> {
        var standing = Set<Map3DScene.ChunkKey>()
        let cell = Double(Land.cellLength)
        for area in areas {
            // The tiles' own projection (`geo.js`, `makeProjection`): metres
            // east and south of the area's origin.
            let phi = area.latitude * .pi / 180
            let metresPerLatitude = 111_132.954 - 559.822 * cos(2 * phi) + 1.175 * cos(4 * phi)
            let metresPerLongitude = 111_412.84 * cos(phi) - 93.5 * cos(3 * phi)
            func world(_ point: CityTileArea.Point) -> (x: Double, y: Double) {
                frame.worldPosition(latitude: area.latitude - Double(point.z) / metresPerLatitude,
                                    longitude: area.longitude + Double(point.x) / metresPerLongitude)
            }
            // The area's corners: none of it in the scene, nothing to read.
            let corners = [CityTileArea.Point(x: area.minX, z: area.minZ), CityTileArea.Point(x: area.maxX, z: area.maxZ)].map(world)
            guard corners[0].x <= region.maxX, corners[1].x >= region.minX, corners[0].y <= region.maxY, corners[1].y >= region.minY else { continue }
            // Decision 352: near, its signs where the pipeline hung them,
            // and `placeAds`' billboards round its station (the tiles'
            // origin) on the walls that look onto a street.
            let near = !isFar
            let origin = point(x: world(CityTileArea.Point(x: 0, z: 0)).x, y: world(CityTileArea.Point(x: 0, z: 0)).y, height: 0)
            var streets = Set<Map3DScene.ChunkKey>()
            if near {
                addTileSigns(area, world: world)
                let box = corners.map { point(x: $0.x, y: $0.y, height: 0) }
                streets = streetCells(within: [(Map3DPoint(min(box[0].x, box[1].x), 0, min(box[0].z, box[1].z)),
                                                Map3DPoint(max(box[0].x, box[1].x), 0, max(box[0].z, box[1].z)))])
            }
            for building in area.buildings {
                let polygons = building.polygons.map { $0.map { $0.map(world) } }
                let points = polygons.flatMap { $0.first ?? [] }
                guard !points.isEmpty else { continue }
                let middle = (x: points.reduce(0) { $0 + $1.x } / Double(points.count), y: points.reduce(0) { $0 + $1.y } / Double(points.count))
                guard contains(x: middle.x, y: middle.y) else { continue }
                let cells = Set(points.map { Map3DScene.ChunkKey(column: Int(($0.x / cell).rounded(.down)), row: Int(($0.y / cell).rounded(.down))) })
                guard cleared.isDisjoint(with: cells) else { continue }
                // The cells under its whole outline, not only its corners.
                let low = (x: points.map(\.x).min() ?? 0, y: points.map(\.y).min() ?? 0)
                let high = (x: points.map(\.x).max() ?? 0, y: points.map(\.y).max() ?? 0)
                for row in Int((low.y / cell).rounded(.down))...Int((high.y / cell).rounded(.down)) {
                    for column in Int((low.x / cell).rounded(.down))...Int((high.x / cell).rounded(.down)) {
                        standing.insert(Map3DScene.ChunkKey(column: column, row: row))
                    }
                }
                let ground = self.ground(x: middle.x, y: middle.y)
                let rings = polygons.map { $0.map { ring in ring.map { point(x: $0.x, y: $0.y, height: 0) } } }
                addRealBuilding(rings, ground: ground, height: max(3, building.height), storeys: max(1, building.storeys),
                                kind: RealKind(usage: building.usage))
                if near, (401...404).contains(building.usage) || building.usage == 413 || building.usage == 414,
                   building.height >= 12, let outline = rings.first?.first, outline.count >= 3 {
                    addRealAds(outline, ground: ground, height: building.height, origin: origin, streets: streets)
                }
            }
        }
        return standing
    }

    /// Decision 352: `placeAds` on a real building of `outline` (scene
    /// points) standing `height` metres on `ground`, by how far it is
    /// from `origin`, its station.
    mutating func addRealAds(_ outline: [Map3DPoint], ground: Float, height: Float, origin: Map3DPoint, streets: Set<Map3DScene.ChunkKey>) {
        let first = outline[0], metre = Double(WorldCoordinate.unitsPerMetre)
        let east = originX / metre + Double(first.x), south = originY / metre + Double(first.z)
        let seed = (Int32(truncatingIfNeeded: Int((east * 10).rounded())), Int32(truncatingIfNeeded: Int((south * 10).rounded())))
        let r = { (salt: Int32) in map3DRandom(seed.0, seed.1, salt: salt) }
        let walls = Self.adWalls(outline) { Self.facesStreet(streets, middle: $0, normal: $1) }
        guard let wall = walls.filter(\.street).max(by: { $0.length < $1.length }) else { return }
        let middle = wall.start + wall.direction * (wall.length / 2)
        let distance = Map3DPoint(middle.x - origin.x, 0, middle.z - origin.z).length
        for ad in Self.ads(walls: walls, foot: ground, height: height, chances: .real(distance: distance), r: r) {
            addSign(ad.sign)
            addAdFrame(ad.sign, roof: ad.roof)
        }
    }

    /// One real building: `polygons` (scene points, each polygon its
    /// outline then its holes) raised `height` metres from `ground`.
    mutating func addRealBuilding(_ polygons: [[[Map3DPoint]]], ground: Float, height: Float, storeys: Int, kind: RealKind) {
        guard let outline = polygons.first?.first, outline.count >= 3 else { return }
        // Seeded from where it stands on the map, not in the scene: the
        // scene's origin moves as track is laid, and the building must not.
        let first = outline[0], metre = Double(WorldCoordinate.unitsPerMetre)
        let east = originX / metre + Double(first.x), south = originY / metre + Double(first.z)
        let seed = (Int32(truncatingIfNeeded: Int((east * 10).rounded())), Int32(truncatingIfNeeded: Int((south * 10).rounded())))
        let r = { (salt: Int32) in map3DRandom(seed.0, seed.1, salt: salt) }
        let box = Self.orientedBox(outline)
        let centre = Map3DPoint(box.centre.x, ground, box.centre.z)
        let area = polygons.reduce(Float(0)) { $0 + abs(Self.signedArea($1.first ?? [])) }

        // Walls, roof and how the faces are painted, by use (decision 235's
        // colours; decision 231's faces).
        var wall: UInt32, roof = Map3DPalette.roof, roofPaint: Map3DPaint? = Self.roofing
        var groundFloor: Float = 0, groundPaint: Map3DPaint?, upperPaint: Map3DPaint?
        let upperFloors = max(1, storeys - 1)
        // Decision 242: the material each kind is faced with.
        let homeFacing = Self.homeMaterial(r(5))
        switch kind {
        case .shophouse:
            wall = Self.pickWall(seed)
            groundFloor = min(3.8, height / 2)
            groundPaint = .bays(r(1) < 0.75 ? Self.pick(Map3DSurface.shops, r(2)) : .shutter, bay: 5.4, floors: 1)
            upperPaint = (storeys <= 5 ? Map3DPaint.bays(r(3) < 0.45 ? .homeBalcony : .homeWindows, bay: 6, floors: upperFloors)
                : Map3DPaint.bays(Self.pick(Map3DSurface.flats, r(3)), bay: 3.2, floors: upperFloors)).on(homeFacing)
        case .flats:
            wall = Self.pickWall(seed)
            if r(1) < 0.5 {
                groundFloor = min(4.2, height / 3)
                groundPaint = .bays(Self.pick(Map3DSurface.shops, r(2)), bay: 5.4, floors: 1)
            }
            upperPaint = Map3DPaint.bays(Self.pick(Map3DSurface.flats, r(3)), bay: 3.2, floors: groundFloor > 0 ? upperFloors : storeys).on(homeFacing)
        case .office:
            let concrete = r(6) < 0.4
            wall = concrete ? Self.pick(Map3DPalette.concreteWalls, seed) : Self.pick(Map3DPalette.officeWalls, seed)
            groundFloor = min(4.6, height / 3)
            groundPaint = .bays(r(1) < 0.5 ? .officeGlass : Self.pick(Map3DSurface.shops, r(2)), bay: r(1) < 0.5 ? 3 : 5.4, floors: 1)
            upperPaint = Map3DPaint.bays(.officeGlass, bay: 3, floors: upperFloors).on(concrete ? .formConcrete : nil)
        case .industry:
            wall = Self.pick(Map3DPalette.shedWalls, seed)
            roof = Self.pick(Map3DPalette.tinRoofs, r(4))
            roofPaint = Self.metal
            upperPaint = Self.metal
        case .civic:
            let concrete = r(6) < 0.5
            wall = concrete ? Self.pick(Map3DPalette.concreteWalls, seed) : Map3DPalette.schoolWalls
            upperPaint = Map3DPaint.bays(.flatWindows, bay: 3.4, floors: storeys).on(concrete ? .formConcrete : .brickTile)
        case .temple:
            wall = Map3DPalette.templeWall
            roof = Map3DPalette.templeRoof
            roofPaint = nil
            upperPaint = Self.plaster.on(.terrazzo)
        case .transport:
            wall = Self.pick(Map3DPalette.concreteWalls, seed)
            upperPaint = Self.concrete.on(.formConcrete)
        }
        // A temple of a single hall under its hipped roof, the walls lower.
        let hipped = kind == .temple && polygons.count == 1 && area < 900 && box.width > 4
        let eaves = hipped ? min(height, max(3.5, height * 0.6)) : height
        // A station's great roof (Kaohsiung's, with its skylights): a thin
        // canopy on pillars, not a solid block.
        let canopy = kind == .transport && (area > 4000 || polygons.contains { $0.count > 1 })
        let wallBottom: Float = canopy ? max(0, eaves - 1.4) : 0
        if canopy {
            wall = Map3DPalette.railTop
            roof = Map3DPalette.tankSteel
            upperPaint = nil
        }
        let far = isFar

        mesh(at: centre) { mesh in
            for polygon in polygons {
                for (index, ring) in polygon.enumerated() where ring.count >= 3 {
                    // Outlines counter-clockwise and holes clockwise in x
                    // and z, so every wall faces away from the building.
                    let ring = (Self.signedArea(ring) > 0) == (index == 0) ? ring : ring.reversed()
                    for (at, a) in ring.enumerated() {
                        let b = ring[(at + 1) % ring.count]
                        let low = Map3DPoint(0, ground + wallBottom, 0)
                        let bottom = (a: Map3DPoint(a.x, 0, a.z) + low, b: Map3DPoint(b.x, 0, b.z) + low)
                        let narrow = (b - a).length < 2
                        if groundFloor > 0 {
                            let up = Map3DPoint(0, groundFloor, 0)
                            mesh.addQuad(bottom.b, bottom.a, bottom.a + up, bottom.b + up, color: wall, paint: narrow ? nil : groundPaint)
                            let top = Map3DPoint(0, eaves, 0)
                            mesh.addQuad(bottom.b + up, bottom.a + up, bottom.a + top, bottom.b + top, color: wall, paint: narrow ? nil : upperPaint)
                        } else {
                            let top = Map3DPoint(0, eaves - wallBottom, 0)
                            mesh.addQuad(bottom.b, bottom.a, bottom.a + top, bottom.b + top, color: wall, paint: narrow ? nil : upperPaint)
                        }
                    }
                }
                // The flat roof over the outline and its holes.
                let lifted = polygon.map { $0.map { Map3DPoint($0.x, ground + eaves, $0.z) } }
                let triangles = Earcut.triangulate(lifted.map { $0.map { (x: Double($0.x), y: Double($0.z)) } })
                mesh.addFlat(lifted.flatMap { $0 }, triangles: triangles, color: roof, paint: roofPaint)
                if canopy {
                    // Its underside, looking down, and a pillar every 24 m
                    // under it.
                    let under = lifted.flatMap { $0 }.map { $0 - Map3DPoint(0, eaves - wallBottom, 0) }
                    var at = 0
                    while at + 2 < triangles.count {
                        var corners = [under[triangles[at]], under[triangles[at + 1]], under[triangles[at + 2]]]
                        if (corners[1] - corners[0]).cross(corners[2] - corners[0]).y > 0 { corners.swapAt(1, 2) }
                        mesh.addFacet(corners, color: Map3DColor.shaded(wall, 0.8))
                        at += 3
                    }
                    let across = Map3DPoint(-box.along.z, 0, box.along.x)
                    let steps = (along: Int(box.length / 24), across: Int(box.width / 24))
                    for i in 0...steps.along {
                        for j in 0...steps.across {
                            let spot = box.centre + box.along * ((Float(i) - Float(steps.along) / 2) * 24)
                                + across * ((Float(j) - Float(steps.across) / 2) * 24)
                            guard Self.inside(spot, polygon) else { continue }
                            mesh.addBox(base: Map3DPoint(spot.x, ground, spot.z), length: 1.2, width: 1.2, height: wallBottom,
                                        top: wall, side: Map3DColor.shaded(wall, 0.9))
                        }
                    }
                }
            }
            let top = Map3DPoint(box.centre.x, ground + eaves, box.centre.z)
            if hipped {
                mesh.addHipRoof(base: top, forward: box.along, length: box.length, width: box.width,
                                rise: min(4.5, box.width * 0.32), overhang: 0.8, sweep: 0.6, color: Map3DPalette.templeRoof)
                Self.addSwallowtailRidge(&mesh, middle: top + Map3DPoint(0, min(4.5, box.width * 0.32), 0), along: box.along,
                                         length: max(2, box.length - box.width))
                return
            }
            // Decision 235's roof clutter: on a house a water tank or a
            // sheet-steel room (頂樓加蓋); on a block, near, its stair
            // house and air conditioners.
            let house = kind == .shophouse || (kind == .flats && storeys <= 6)
            switch kind {
            case _ where house:
                // Only on a house's roof, not a long terrace's or a hall's.
                guard box.length > 4, box.width > 3.2, box.length < 30, box.width < 16 else { break }
                let spot = top - box.along * (box.length / 4)
                if r(6) < 0.55 {
                    let tank = r(7) < 0.5 ? Map3DPalette.tankBlue : Map3DPalette.tankSteel
                    mesh.addBox(base: spot, forward: box.along, length: 1.6, width: 1.6, height: 2.2, top: tank, side: tank)
                } else if r(6) < 0.8 {
                    let tin = Self.pick(Map3DPalette.tinRoofs, r(11))
                    let length = box.length / 2 - 0.4, width = box.width - 0.8
                    mesh.addBox(base: spot, forward: box.along, length: length, width: width, height: 2.4, top: tin,
                                side: Map3DColor.shaded(Map3DPalette.shedWalls[0], 0.95), frontPaint: Self.metal, flankPaint: Self.metal,
                                capped: false)
                    mesh.addGableRoof(base: spot + Map3DPoint(0, 2.4, 0), forward: box.along, length: length, width: width,
                                      rise: width / 2 * 0.36, overhang: 0.3, color: tin, gable: Map3DPalette.shedWalls[0], paint: Self.metal)
                }
            case .flats, .office, .civic:
                if !far {
                    Self.addRoofPlant(&mesh, on: top, forward: box.along, length: box.length * 0.8, width: box.width * 0.8, r: r, salt: 30)
                }
            default:
                break
            }
        }
        // Decision 232: the shadow round its foot, wider under a taller
        // one (none under a canopy, whose box is mostly open ground).
        guard !canopy else { return }
        addShadow(centre: centre, forward: box.along, length: box.length, width: box.width, spread: min(6, 2 + height * 0.08), darkness: 0.32)
    }

    /// Whether `point` lies inside `polygon`'s outline and in none of its
    /// holes (in x and z).
    static func inside(_ point: Map3DPoint, _ polygon: [[Map3DPoint]]) -> Bool {
        polygon.enumerated().allSatisfy { index, ring in
            var crossings = false
            for (at, a) in ring.enumerated() {
                let b = ring[(at + 1) % ring.count]
                if (a.z > point.z) != (b.z > point.z), point.x < a.x + (point.z - a.z) / (b.z - a.z) * (b.x - a.x) {
                    crossings.toggle()
                }
            }
            return crossings == (index == 0)
        }
    }

    /// The signed area of `ring` in x and z: positive when it
    /// turns counter-clockwise from x toward z.
    static func signedArea(_ ring: [Map3DPoint]) -> Float {
        var sum: Float = 0
        for (at, a) in ring.enumerated() {
            let b = ring[(at + 1) % ring.count]
            sum += a.x * b.z - b.x * a.z
        }
        return sum / 2
    }

    /// The box round `ring` turned along its longest side: its middle,
    /// that side's direction, and its length along and width across.
    static func orientedBox(_ ring: [Map3DPoint]) -> (centre: Map3DPoint, along: Map3DPoint, length: Float, width: Float) {
        var along = Map3DPoint(1, 0, 0), longest: Float = 0
        for (at, a) in ring.enumerated() {
            let side = ring[(at + 1) % ring.count] - a
            let flat = Map3DPoint(side.x, 0, side.z)
            if flat.length > longest, let direction = flat.normalized {
                longest = flat.length
                along = direction
            }
        }
        let across = Map3DPoint(-along.z, 0, along.x)
        let onAlong = ring.map { $0.dot(along) }, onAcross = ring.map { $0.dot(across) }
        let (lowA, highA) = (onAlong.min() ?? 0, onAlong.max() ?? 0), (lowC, highC) = (onAcross.min() ?? 0, onAcross.max() ?? 0)
        let centre = along * ((lowA + highA) / 2) + across * ((lowC + highC) / 2)
        return (Map3DPoint(centre.x, 0, centre.z), along, highA - lowA, highC - lowC)
    }
}
