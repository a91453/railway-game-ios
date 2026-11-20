import Foundation
import GameCore

// Decision 239: a real-world map's real buildings round Kaohsiung and
// Taichung Stations, from the 3D city preview's tiles (``CityTileArea``):
// each footprint raised to its height in the 3D map's own look, the colours
// and roof clutter of decision 235, by what the building is used for.

extension Map3DScene.Builder {
    /// What a real building is drawn as, by its usage code
    /// (`Web/CityView/tools/pipeline/taiwan.mjs`, `usageOf`).
    enum RealKind: Hashable {
        /// 413: a 透天厝 street's shophouse, shops under homes.
        case shophouse
        /// Decision 389: a home of a few storeys, homes to the ground (a
        /// footprint's, its use residential or unknown).
        case house
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
        /// Decision 699: an airport's passenger terminal, by its stands.
        case terminal
        /// Decision 765: a hall a street sees no windows on: a stadium, a
        /// sports hall or grandstand, a substation, or a great low hall of
        /// no known use (a market's, a works' or a mall's).
        case hall

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
        var cover = RealCover()
        defer { tileCover = cover }
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
            // Decision 610: and the street fronts by the same streets.
            facadeStreets = near && buildsFacades ? streets : nil
            defer { facadeStreets = nil }
            for building in area.buildings {
                let polygons = building.polygons.map { $0.map { $0.map(world) } }
                let points = polygons.flatMap { $0.first ?? [] }
                guard !points.isEmpty else { continue }
                let middle = (x: points.reduce(0) { $0 + $1.x } / Double(points.count), y: points.reduce(0) { $0 + $1.y } / Double(points.count))
                guard contains(x: middle.x, y: middle.y) else { continue }
                let cells = Set(points.map { Map3DScene.ChunkKey(column: Int(($0.x / cell).rounded(.down)), row: Int(($0.y / cell).rounded(.down))) })
                guard cleared.isDisjoint(with: cells) else { continue }
                let rings = polygons.map { $0.map { ring in ring.map { point(x: $0.x, y: $0.y, height: 0) } } }
                // MRT-SHELL-CLEAR-OUTLINE: nor under the track or a station's own building.
                guard !rings.contains(where: { underRailway($0.first ?? []) }) else { continue }
                // Cleared for a building of the player's: its cells still
                // keep no city lot.
                let drawn = !rings.contains(where: { onPlacedGround($0.first ?? []) })
                // The cells under its whole outline, not only its corners;
                // decision 723: and how much of each it covers.
                for polygon in polygons { standing.formUnion(count(polygon, drawn: drawn, into: &cover)) }
                guard drawn else { continue }
                let ground = self.ground(x: middle.x, y: middle.y)
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
    mutating func addRealBuilding(_ polygons: [[[Map3DPoint]]], ground: Float, height: Float, storeys: Int, kind given: RealKind) {
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
        // Decision 765: a hut drawn as a shed, a great low hall as a hall.
        var kind = Self.drawnKind(given, area: area, width: box.width, storeys: storeys)
        // Decision 802: on a Finnish map no hall is a Taiwanese temple (a
        // church is drawn as a public building), and a house of three
        // floors or more is a block of flats.
        let nordic = look.buildings == .nordic, clutter = look.buildings.hasRoofClutter
        if !look.buildings.drawsTaiwanTemples, kind == .temple { kind = .civic }
        if nordic, kind == .house, storeys > 2 { kind = .flats }
        // Decision 765: windows a floor high, not stretched up a hall
        // whose storeys are fewer than its height holds.
        func floors(_ high: Float, _ storeys: Int) -> Int { max(storeys, Int(high / Self.tallestStorey)) }

        // Walls, roof and how the faces are painted, by use (decision 235's
        // colours; decision 231's faces).
        var wall: UInt32, roof = Self.pickRoof(r(1040), low: storeys <= 3), roofPaint: Map3DPaint? = Self.roofing
        var groundFloor: Float = 0, groundPaint: Map3DPaint?, upperPaint: Map3DPaint?
        let upperFloors = max(1, storeys - 1)
        // Decision 242: the material each kind is faced with.
        let homeFacing = Self.homeMaterial(r(5))
        switch kind {
        case .shophouse:
            wall = Self.pickWall(seed)
            groundFloor = min(3.8, height / 2)
            groundPaint = .bays(r(1) < 0.75 ? Self.pick(Map3DSurface.shops, r(2)) : .shutter, bay: 5.4, floors: 1)
            let upper = floors(height - groundFloor, upperFloors)
            upperPaint = (storeys <= 5 ? Map3DPaint.bays(r(3) < 0.45 ? .homeBalcony : .homeWindows, bay: 6, floors: upper)
                : Map3DPaint.bays(Self.pick(Map3DSurface.flats, r(3)), bay: 3.2, floors: upper)).on(homeFacing)
        case .house:
            wall = Self.pickWall(seed)
            upperPaint = Map3DPaint.bays(r(3) < 0.45 ? .homeBalcony : .homeWindows, bay: 6, floors: floors(height, storeys)).on(homeFacing)
        case .flats:
            wall = Self.pickWall(seed)
            if r(1) < 0.5 {
                groundFloor = min(4.2, height / 3)
                groundPaint = .bays(Self.pick(Map3DSurface.shops, r(2)), bay: 5.4, floors: 1)
            }
            upperPaint = Map3DPaint.bays(Self.pick(Map3DSurface.flats, r(3)), bay: 3.2,
                                         floors: floors(height - groundFloor, groundFloor > 0 ? upperFloors : storeys)).on(homeFacing)
        case .office:
            let concrete = r(6) < 0.4
            wall = concrete ? Self.pick(Map3DPalette.cityConcreteWalls, seed) : Self.pick(Map3DPalette.cityOfficeWalls, seed)
            groundFloor = min(4.6, height / 3)
            groundPaint = .bays(r(1) < 0.5 ? .officeGlass : Self.pick(Map3DSurface.shops, r(2)), bay: r(1) < 0.5 ? 3 : 5.4, floors: 1)
            upperPaint = Map3DPaint.bays(.officeGlass, bay: 3, floors: floors(height - groundFloor, upperFloors)).on(concrete ? .formConcrete : nil)
        case .industry:
            wall = Self.pick(Map3DPalette.shedWalls, seed)
            roof = Self.pick(Map3DPalette.tinRoofs, r(4))
            roofPaint = Self.metal
            upperPaint = Self.metal
        case .civic:
            let concrete = r(6) < 0.5
            wall = concrete ? Self.pick(Map3DPalette.cityConcreteWalls, seed) : Map3DPalette.schoolWalls
            upperPaint = Map3DPaint.bays(.flatWindows, bay: 3.4, floors: floors(height, storeys)).on(concrete ? .formConcrete : .brickTile)
        case .temple:
            wall = Map3DPalette.templeWall
            roof = Map3DPalette.templeRoof
            roofPaint = nil
            upperPaint = Self.plaster.on(.terrazzo)
        case .transport:
            wall = Self.pick(Map3DPalette.cityConcreteWalls, seed)
            upperPaint = Self.concrete.on(.formConcrete)
        case .terminal:
            // Decision 698's terminal: white walls of glass under a
            // blue-grey roof, which stands off the pale ground.
            wall = Airfield.terminalWall
            roof = Airfield.terminalRoof
            roofPaint = Self.metal
            upperPaint = Map3DPaint.bays(.officeGlass, bay: 4, floors: storeys)
        case .hall:
            // Decision 765: walls a street sees no windows in (decision
            // 764's hall colours, below).
            wall = Self.pick(Map3DPalette.cityConcreteWalls, seed)
            upperPaint = Self.concrete.on(.formConcrete)
        }
        // Decision 802: Finland's houses and blocks: boards or plaster in
        // its own colours, a window to each bay, no shutter below and no
        // tile on the walls.
        // Whether its roof's colour already has the snow in it.
        var snowedRoof = false
        if nordic {
            switch kind {
            case .house where storeys <= 2, .shophouse where storeys <= 2:
                wall = Self.pick(Map3DNordic.houseWalls, r(1043))
                roof = Self.pick(Map3DNordic.pitchedRoofs, r(1040))
                snowedRoof = true
                (groundFloor, groundPaint) = (0, nil)
                upperPaint = Map3DPaint.bays(.flatWindows, bay: 3.4, floors: floors(height, storeys))
            case .shophouse, .flats:
                wall = Self.pick(Map3DNordic.blockWalls, r(1043))
                roof = Map3DNordic.flatRoof
                snowedRoof = true
                if kind == .shophouse {
                    groundFloor = min(3.8, height / 3)
                    groundPaint = .bays(Self.pick(Map3DSurface.shops, r(2)), bay: 5.4, floors: 1)
                } else {
                    (groundFloor, groundPaint) = (0, nil)
                }
                upperPaint = Map3DPaint.bays(Self.pick(Map3DSurface.flats, r(3)), bay: 3.2,
                                             floors: floors(height - groundFloor, groundFloor > 0 ? upperFloors : storeys))
            case .civic:
                wall = Self.pick(Map3DNordic.blockWalls, r(1043))
                upperPaint = Map3DPaint.bays(.flatWindows, bay: 3.4, floors: floors(height, storeys))
            default:
                break
            }
        }
        // Decision 812: Hong Kong's towers, tenements, village houses,
        // glass offices and public buildings, under grey concrete roofs.
        let hongKong = look.buildings == .hongKong
        if hongKong, let faces = Self.hongKongFaces(kind, storeys: storeys, height: height, r: r, floors: floors) {
            (wall, roof, groundFloor, groundPaint, upperPaint) = (faces.wall, faces.roof, faces.groundFloor, faces.groundPaint, faces.upperPaint)
            roofPaint = faces.metalRoof ? Self.metal : Self.roofing
        }
        // Decision 817: a tower's windows of its own kind, its bays, its
        // floors and the bays of its narrow walls its own.
        let facadeLook = Map3DFacadeVariety.look(kind, storeys: storeys, hongKong: hongKong, nordic: nordic,
                                                 solid: hongKong ? r(6) >= 0.65 : r(6) < 0.4, r: r)
        var sidePaint: Map3DPaint?
        if let facadeLook {
            let detail = upperPaint?.detail
            upperPaint = facadeLook.paint(high: height - groundFloor, detail: detail)
            sidePaint = facadeLook.paint(high: height - groundFloor, detail: detail, side: true)
        }
        // Decision 764: a big low hall (an arena, a gym, a market) its own
        // walls and sheet-steel roof; and every city building's walls a
        // little lighter or darker by where it stands. Decision 765: and
        // every hall drawn with no windows.
        if kind == .hall || ([.shophouse, .office, .civic].contains(kind) && area >= 3000 && storeys <= 6) {
            wall = Self.pick(Map3DPalette.hallWalls, seed)
            roof = Self.pick(Map3DPalette.hallRoofs, r(1042))
            roofPaint = Self.metal
            snowedRoof = false
            // Decision 812: Hong Kong's podiums and malls under concrete.
            if hongKong {
                roof = Self.pick(Map3DHongKong.roofs, r(1042))
                roofPaint = Self.roofing
            }
        }
        if kind != .temple, kind != .terminal { wall = Self.varied(wall, r(1041)) }
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
        // Decision 802: a northern map's roofs under snow, and a Finnish
        // house's pitched.
        if look.snow, !snowedRoof { roof = Map3DSnowGround.roof(roof) }
        let pitched = look.buildings.pitchesLowRoofs && !canopy && !hipped
            && Self.isPitched(kind, storeys: storeys, area: area, single: polygons.count == 1 && polygons[0].count == 1, box: box)
        if pitched {
            roofPaint = nil
        } else if nordic, snowedRoof {
            // A low house no pitched roof spans: a flat one.
            roof = Map3DNordic.flatRoof
        }
        let far = isFar
        // Decision 455: afar, an outline of four corners each within
        // ``rectangleReach`` of the box round it is drawn as that box (as
        // an instance, ``Map3DBoxInstance``): its walls, their bands and
        // its roof painted as below.
        let rectangle = far && !canopy && !hipped && polygons.count == 1 && polygons[0].count == 1 && Self.isRectangle(outline, box)

        mesh(at: centre) { mesh in
            if rectangle {
                // Its front faces along, as wide as the box; its flanks as
                // long. A face under 2 m is left plain, as a wall is.
                // Decision 765: nor one narrower than half a bay of it.
                func plain(_ side: Float, _ paint: Map3DPaint?) -> Map3DPaint? { side < Self.plainBelow(paint) ? nil : paint }
                var bottom = Map3DPoint(box.centre.x, ground, box.centre.z), upper = height
                if groundFloor > 0 {
                    mesh.addBox(base: bottom, forward: box.along, length: box.length, width: box.width, height: groundFloor, top: roof, side: wall,
                                frontPaint: plain(box.width, groundPaint), flankPaint: plain(box.length, groundPaint), capped: false, shaded: false)
                    bottom.y += groundFloor
                    upper -= groundFloor
                }
                // Decision 817: its narrow ends' bays a tower's own.
                let ends = box.width < box.length * Map3DFacadeVariety.narrowShare ? sidePaint ?? upperPaint : upperPaint
                mesh.addBox(base: bottom, forward: box.along, length: box.length, width: box.width, height: upper, top: roof, side: wall,
                            topPaint: roofPaint, frontPaint: plain(box.width, ends), flankPaint: plain(box.length, upperPaint), shaded: false)
            }
            for polygon in polygons where !rectangle {
                for (index, ring) in polygon.enumerated() where ring.count >= 3 {
                    // Outlines counter-clockwise and holes clockwise in x
                    // and z, so every wall faces away from the building.
                    let ring = (Self.signedArea(ring) > 0) == (index == 0) ? ring : ring.reversed()
                    // Decision 817: a narrow wall of a tower takes its side bays.
                    let longestWall = sidePaint == nil ? 0 : ring.indices.map { (ring[($0 + 1) % ring.count] - ring[$0]).length }.max() ?? 0
                    for (at, a) in ring.enumerated() {
                        let b = ring[(at + 1) % ring.count]
                        let low = Map3DPoint(0, ground + wallBottom, 0)
                        let bottom = (a: Map3DPoint(a.x, 0, a.z) + low, b: Map3DPoint(b.x, 0, b.z) + low)
                        // Decision 765: a wall narrower than half a bay of
                        // its paint, or a piece of a curved wall, is left
                        // plain, not given a window squeezed into it.
                        let length = (b - a).length
                        let curve = Self.isCurvePiece(ring[(at + ring.count - 1) % ring.count], a, b, ring[(at + 2) % ring.count])
                        func plain(_ given: Map3DPaint?) -> Map3DPaint? {
                            let paint = given == upperPaint && length < longestWall * Map3DFacadeVariety.narrowShare ? sidePaint ?? given : given
                            return length < Self.plainBelow(paint) || (curve && length < Self.longestCurvePiece) ? nil : paint
                        }
                        if groundFloor > 0 {
                            let up = Map3DPoint(0, groundFloor, 0)
                            mesh.addQuad(bottom.b, bottom.a, bottom.a + up, bottom.b + up, color: wall, paint: plain(groundPaint))
                            let top = Map3DPoint(0, eaves, 0)
                            mesh.addQuad(bottom.b + up, bottom.a + up, bottom.a + top, bottom.b + top, color: wall, paint: plain(upperPaint))
                        } else {
                            let top = Map3DPoint(0, eaves - wallBottom, 0)
                            mesh.addQuad(bottom.b, bottom.a, bottom.a + top, bottom.b + top, color: wall, paint: plain(upperPaint))
                        }
                    }
                }
                // The flat roof over the outline and its holes.
                let lifted = polygon.map { $0.map { Map3DPoint($0.x, ground + eaves, $0.z) } }
                let triangles = Earcut.triangulate(lifted.map { $0.map { (x: Double($0.x), y: Double($0.z)) } })
                if pitched {
                    // Decision 802: the ridge along the house, the roof
                    // over its box (4 triangles more than the flat one).
                    mesh.addGableRoof(base: Map3DPoint(box.centre.x, ground + eaves, box.centre.z), forward: box.along, length: box.length,
                                      width: box.width, rise: box.width / 2 * Map3DNordic.pitch, overhang: 0.5, color: roof, gable: wall)
                } else {
                    mesh.addFlat(lifted.flatMap { $0 }, triangles: triangles, color: roof, paint: roofPaint)
                }
                // Decision 699: a terminal's white roof edge, and on a
                // plain hall or pier its skylight and ribs.
                if kind == .terminal, !far { Self.addTerminalRoof(to: &mesh, outline: lifted[0], box: box, plain: polygon.count == 1) }
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
            // Decision 812: a Hong Kong roof's crown, hut or plant.
            if hongKong {
                Self.addHongKongRoof(&mesh, kind: kind, storeys: storeys, wall: wall, top: top, box: box, far: far, r: r)
                return
            }
            // Decision 235's roof clutter: on a house a water tank or a
            // sheet-steel room (頂樓加蓋); on a block, near, its stair
            // house and air conditioners.
            let house = kind == .shophouse || kind == .house || (kind == .flats && storeys <= 6)
            switch kind {
            case _ where house:
                // Only on a house's roof, not a long terrace's or a hall's.
                // Decision 802: and only where roofs have them.
                guard clutter, box.length > 4, box.width > 3.2, box.length < 30, box.width < 16 else { break }
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
        // Decision 817: near, what stands out of a tower's walls.
        if let facadeLook, !far, !canopy, !hipped, polygons.count == 1 || polygons.allSatisfy({ $0.count == 1 }) {
            addTowerRelief(outline, centre: centre, bottom: ground + groundFloor, top: ground + height, look: facadeLook, wall: wall, r: r)
        }
        // Decision 610: near, what stands out of its street fronts (none
        // on a temple's hall or a station's roof, whose kinds have none),
        // a rooftop room only where decision 235's clutter left the roof.
        if !far, buildsFacades, look.buildings.hasStreetFronts, facadeStreets != nil, !canopy, !hipped {
            var street = FrontStreetLevel(height: groundFloor)
            switch kind {
            // Decision 812: no arcade where shops open on the pavement.
            case .shophouse: street.arcade = look.buildings.hasArcades; street.shops = hongKong || r(1) < 0.75
            case .flats: street.arcade = groundFloor > 0 && look.buildings.hasArcades; street.shops = groundFloor > 0
            case .office: street.shops = r(1) >= 0.5
            default: break
            }
            let small = box.length > 4 && box.width > 3.2 && box.length < 30 && box.width < 16
            let cluttered = (kind == .shophouse || kind == .house || (kind == .flats && storeys <= 6)) && small && r(6) < 0.8
            addRealFacade(outline, centre: centre, ground: ground, height: height, storeys: storeys, kind: kind, wall: wall, street: street,
                          rooms: !cluttered && look.buildings.hasArcades, r: r)
        }
        // Decision 232: the shadow round its foot, wider under a taller
        // one (none under a canopy, whose box is mostly open ground).
        guard !canopy else { return }
        addShadow(centre: centre, forward: box.along, length: box.length, width: box.width, spread: min(6, 2 + height * 0.08), darkness: 0.32)
    }

    /// Decision 765: what a building of `kind` (by its use) is drawn as,
    /// by its `area` (m²), its oriented box's `width` (m) and `storeys`:
    /// a hut of a house's, a shop's or an office's use under
    /// ``largestHut`` as a sheet-steel shed (鐵皮屋), its walls plain; a
    /// home or shop of five storeys or fewer over ``smallestHall`` and
    /// ``narrowestHall`` both ways as a ``RealKind/hall``: no row of
    /// houses is that deep, so it is a market, a works or a mall.
    static func drawnKind(_ kind: RealKind, area: Float, width: Float, storeys: Int) -> RealKind {
        let homes: Set<RealKind> = [.house, .shophouse, .flats]
        if homes.union([.office, .civic]).contains(kind), area < largestHut, storeys <= 2 { return .industry }
        if homes.contains(kind), storeys <= 5, area >= smallestHall, width >= narrowestHall { return .hall }
        return kind
    }

    /// Decision 765: the largest hut drawn as a shed, m² (some 4 × 5 m).
    static let largestHut: Float = 20
    /// Decision 765: the smallest great hall, m², and its least width, m:
    /// two rows of shophouses back to back are some 30–36 m deep.
    static let smallestHall: Float = 2_500
    static let narrowestHall: Float = 45
    /// Decision 765: the tallest a floor of windows is drawn, m.
    static let tallestStorey: Float = 4.2
    /// Decision 765: the longest wall a curve is cut into that is left
    /// plain, m, and the most it turns at either end, degrees.
    static let longestCurvePiece: Float = 8
    static let curveTurn: Float = 25

    /// Decision 765: the narrowest wall that takes `paint`: half a bay of
    /// it, at least 2 m (a narrower one is left plain).
    static func plainBelow(_ paint: Map3DPaint?) -> Float {
        if case let .bays(bay, _)? = paint?.fit { return max(2, bay / 2) }
        return 2
    }

    /// Decision 765: whether the wall from `a` to `b`, between the walls
    /// from `before` and to `after`, is a piece of a curve: it turns no
    /// more than ``curveTurn`` at both its ends.
    static func isCurvePiece(_ before: Map3DPoint, _ a: Map3DPoint, _ b: Map3DPoint, _ after: Map3DPoint) -> Bool {
        func turn(_ p: Map3DPoint, _ q: Map3DPoint, _ s: Map3DPoint) -> Float {
            guard let one = Map3DPoint(q.x - p.x, 0, q.z - p.z).normalized, let two = Map3DPoint(s.x - q.x, 0, s.z - q.z).normalized
            else { return 180 }
            return acos(max(-1, min(1, one.dot(two)))) * 180 / .pi
        }
        let limit = curveTurn
        let first = turn(before, a, b), second = turn(a, b, after)
        return first > 0.5 && second > 0.5 && first <= limit && second <= limit
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
    /// Decision 455: how far a corner of an outline drawn afar as its box
    /// may lie from the box's, in metres: under 1.5 steps of the real
    /// footprints' own grid (``FootprintTiles``, 4,096 to a tile of zoom
    /// 16, some 0.135 m in Taiwan) and a tenth of a pixel from where the
    /// city is drawn simplified.
    static let rectangleReach: Float = 0.2

    /// Decision 455: whether `ring` has four corners, each within
    /// ``rectangleReach`` of a different corner of `box`, its
    /// ``orientedBox(_:)``.
    static func isRectangle(_ ring: [Map3DPoint], _ box: (centre: Map3DPoint, along: Map3DPoint, length: Float, width: Float)) -> Bool {
        guard ring.count == 4 else { return false }
        let corners = Map3DBoxInstance.corners(base: box.centre, along: box.along, length: box.length, width: box.width, height: 0).ground
        func distance(_ a: Map3DPoint, _ b: Map3DPoint) -> Float { Map3DPoint(a.x - b.x, 0, a.z - b.z).length }
        let nearest = ring.map { point in corners.indices.min { distance(point, corners[$0]) < distance(point, corners[$1]) } ?? 0 }
        return Set(nearest).count == 4 && zip(ring, nearest).allSatisfy { distance($0, corners[$1]) <= rectangleReach }
    }

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
