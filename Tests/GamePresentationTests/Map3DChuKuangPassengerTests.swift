import Testing
@testable import GamePresentation

struct Map3DChuKuangPassengerTests {
    @Test func unitsAreDistinctAndLegal() {
        for role in Map3DChuKuangPassenger.Role.allCases {
            let near=Map3DChuKuangPassenger.model(role), far=Map3DChuKuangPassenger.model(role,far:true)
            #expect(near.triangleCount < 15_000)
            #expect(far.triangleCount < near.triangleCount)
            #expect(far.triangleCount < 4_100)
            #expect(abs(near.minimum.z) < 0.0001)
            #expect(abs(near.length-20) < 0.001)
            #expect(near.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
        #expect(Map3DChuKuangPassenger.windows(.standard,left:true).count == 9)
        #expect(Map3DChuKuangPassenger.windows(.standard,left:true).filter{$0.1>1}.count == 5)
        #expect(Map3DChuKuangPassenger.model(.standard).vertices.map(\.x) != Map3DChuKuangPassenger.model(.conductorStudy).vertices.map(\.x))
    }
    @Test func studyDoesNotReplaceOperatingCars() {
        let names=Set(Map3DModelPack.standard.models.map(\.name))
        #expect(!names.contains("chukuang-standard"))
        #expect(names.contains("set-E500CK-car"))
        #expect(names.contains("pp-ppt1000"))
    }
}
