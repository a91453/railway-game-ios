import GameCore
import GamePresentation
import MapKit
import XCTest

/// Decision 463: on a real-world map that buys its land (the whole island,
/// decision 167) the railway and the bus stops lay about a kilometre off
/// Apple's map in Taipei (player report 90.1), though the stops' own
/// coordinates were right. Only MapKit can say where it draws a place, so
/// these run on the Simulator; they launch no app, they ask MapKit's own
/// functions in the test's process.
///
/// The places are each a city a player starts from, in the world laid
/// round it (``RealWorldExpansion``), so the farthest of them lies some
/// 190 km from the world's anchor.
final class BaseMapProjectionUITests: XCTestCase {
    private static let places = ["tra-keelung", "tra-taipei", "tra-hsinchu", "tra-taichung", "tra-hualien", "tra-tainan", "tra-kaohsiung", "tra-pingtung", "tra-taitung"]

    /// Each city, in the world laid round it, and the island's corners in
    /// the same world: how far MapKit draws them from where the app asks
    /// for them, in metres.
    private func offsets(of mapPoint: (RealWorldFrame, Double, Double) -> MKMapPoint) throws -> [(String, Double)] {
        var offsets: [(String, Double)] = []
        for id in Self.places {
            let place = try XCTUnwrap(RealWorldPlace.all.first { $0.id == id }, id)
            let expansion = try XCTUnwrap(RealWorldExpansion(around: place.anchor), id)
            let frame = expansion.frame
            let spots = [
                (id, place.anchor.latitudeDegrees, place.anchor.longitudeDegrees),
                ("\(id) north-east", WholeTaiwan.north, WholeTaiwan.east),
                ("\(id) south-west", WholeTaiwan.south, WholeTaiwan.west),
            ]
            for (name, latitude, longitude) in spots {
                let world = frame.worldPosition(latitude: latitude, longitude: longitude)
                let asked = mapPoint(frame, world.x, world.y)
                let truth = MKMapPoint(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                offsets.append((name, asked.distance(to: truth)))
            }
        }
        return offsets
    }

    /// The map point the app gives MapKit for a world point (decision 463,
    /// ``RealWorldFrame/mapPoint(worldX:worldY:)``) is where MapKit draws
    /// the place the game put there, within a metre, all over the island.
    func testTheBaseMapDrawsEachPlaceUnderTheGamesPoint() throws {
        let offsets = try offsets { frame, x, y in
            let point = frame.mapPoint(worldX: x, worldY: y)
            return MKMapPoint(x: point.x, y: point.y)
        }
        let report = offsets.map { "\($0.0) \(Int($0.1.rounded())) m" }.joined(separator: "; ")
        for (name, metres) in offsets {
            XCTAssertLessThan(metres, 1, "\(name): \(report)")
        }
    }

    /// Before decision 463 the app scaled world metres by MapKit's own
    /// `MKMapPointsPerMeterAtLatitude` at the anchor. This measures how far
    /// that put each place, so the decision's table can be checked again.
    func testMapKitsOwnScaleAgreesWithTheGames() throws {
        let offsets = try offsets { frame, x, y in
            let metres = frame.metresFromAnchor(worldX: x, worldY: y)
            let anchor = MKMapPoint(CLLocationCoordinate2D(latitude: frame.anchor.latitudeDegrees, longitude: frame.anchor.longitudeDegrees))
            let perMetre = MKMapPointsPerMeterAtLatitude(frame.anchor.latitudeDegrees)
            return MKMapPoint(x: anchor.x + metres.east * perMetre, y: anchor.y + metres.south * perMetre)
        }
        let latitude = 23.6
        let ratio = MKMapPointsPerMeterAtLatitude(latitude) / RealWorldFrame.mapPointsPerMetre(atLatitude: latitude)
        let report = "MapKit/game scale at 23.6°: \(ratio); " + offsets.map { "\($0.0) \(Int($0.1.rounded())) m" }.joined(separator: "; ")
        for (name, metres) in offsets {
            XCTAssertLessThan(metres, 1, "\(name): \(report)")
        }
    }
}
