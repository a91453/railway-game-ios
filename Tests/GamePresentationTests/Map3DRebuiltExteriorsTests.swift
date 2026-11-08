@testable import GamePresentation
import XCTest

/// Review L14-6: chunks built again after the track changed (decision 358's
/// rebuild) keep the station studies standing elsewhere, take those that
/// stand in them now, and drop one that no longer stands there (new track
/// cut it to less than half): on main it stayed in the scene's list, though
/// it was no longer drawn.
final class Map3DRebuiltExteriorsTests: XCTestCase {
    private func study(_ station: Map3DStationExteriorBatch1.Station, at x: Float) -> Map3DStationExterior {
        Map3DStationExterior(station: station, origin: Map3DPoint(x, 0, 0), outlines: [], kept: (1, 1), near: Map3DMesh(), far: Map3DMesh())
    }

    func testAStudyCutAwayInTheChunksBuiltAgainGoes() {
        let old = [study(.taichungTRA, at: 10), study(.hsinchuTRA, at: 900)]
        let block: (Map3DPoint) -> Bool = { $0.x < 500 }
        // Built again, the Taichung study no longer stands.
        XCTAssertEqual(Map3DScene.exteriors(old, rebuilt: [], in: block).map(\.station), [.hsinchuTRA])
        // It still stands: the one built again, once.
        XCTAssertEqual(Map3DScene.exteriors(old, rebuilt: [study(.taichungTRA, at: 10)], in: block).map(\.station), [.hsinchuTRA, .taichungTRA])
        // One the rebuild stood only in its apron is not drawn by it.
        XCTAssertEqual(Map3DScene.exteriors(old, rebuilt: [study(.hsinchuTRA, at: 900)], in: block).map(\.station), [.hsinchuTRA])
        XCTAssertEqual(Map3DScene.exteriors([], rebuilt: [study(.hualienTRA, at: 20)], in: block).map(\.station), [.hualienTRA])
    }
}
