import Foundation
@testable import GamePresentation
import XCTest

/// The loopback server of the 3D city view (decision 152): which file a
/// request asks for, and what it answers.
final class CityViewServingTests: XCTestCase {
    func testTheRootIsTheIndexPage() {
        XCTAssertEqual(CityViewServing.file(requestHead: "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"), "index.html")
    }

    func testAFileIsServedWithoutItsQuery() {
        XCTAssertEqual(
            CityViewServing.file(requestHead: "GET /index.html?area=kaohsiung&radius=400 HTTP/1.1\r\n\r\n"), "index.html")
        XCTAssertEqual(
            CityViewServing.file(requestHead: "GET /tiles/kaohsiung/t_0_-1.bin HTTP/1.1\r\n\r\n"), "tiles/kaohsiung/t_0_-1.bin")
        XCTAssertEqual(CityViewServing.file(requestHead: "HEAD /assets/index.js#x HTTP/1.1\r\n\r\n"), "assets/index.js")
    }

    func testPercentEncodedNamesAreDecoded() {
        XCTAssertEqual(CityViewServing.file(requestHead: "GET /a%20b/c.json HTTP/1.1\r\n\r\n"), "a b/c.json")
    }

    func testAPathCannotLeaveTheFolder() {
        for target in ["/../secret", "/tiles/../../x", "/%2e%2e/x", "/.hidden", "/a\\b", "/a%00b", "relative"] {
            XCTAssertNil(CityViewServing.file(requestHead: "GET \(target) HTTP/1.1\r\n\r\n"), target)
        }
    }

    func testOnlyGetAndHeadAreServed() {
        XCTAssertNil(CityViewServing.file(requestHead: "POST /index.html HTTP/1.1\r\n\r\n"))
        XCTAssertNil(CityViewServing.file(requestHead: "GET /index.html\r\n\r\n"))
        XCTAssertNil(CityViewServing.file(requestHead: ""))
        XCTAssertTrue(CityViewServing.isHead("HEAD / HTTP/1.1\r\n\r\n"))
        XCTAssertFalse(CityViewServing.isHead("GET / HTTP/1.1\r\n\r\n"))
    }

    func testTheContentTypeFollowsTheExtension() {
        XCTAssertEqual(CityViewServing.contentType(of: "index.html"), "text/html; charset=utf-8")
        XCTAssertEqual(CityViewServing.contentType(of: "assets/tileWorker-B9G7ZFLA.js"), "text/javascript; charset=utf-8")
        XCTAssertEqual(CityViewServing.contentType(of: "tiles/kaohsiung/manifest.json"), "application/json; charset=utf-8")
        XCTAssertEqual(CityViewServing.contentType(of: "textures/grass/diff.JPG"), "image/jpeg")
        XCTAssertEqual(CityViewServing.contentType(of: "tiles/kaohsiung/terrain.bin"), "application/octet-stream")
    }

    func testTheHeadOfAnAnswer() {
        let ok = String(decoding: CityViewServing.responseHead(contentType: "image/png", length: 42), as: UTF8.self)
        XCTAssertEqual(ok, "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: 42\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n")
        let missing = String(decoding: CityViewServing.responseHead(contentType: nil, length: 0), as: UTF8.self)
        XCTAssertTrue(missing.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
    }

    func testTheStartPageIsTheLightKaohsiungView() {
        XCTAssertEqual(CityViewServing.file(requestHead: "GET \(CityViewServing.startPath) HTTP/1.1\r\n\r\n"), "index.html")
        XCTAssertTrue(CityViewServing.startPath.contains("area=kaohsiung"))
    }
}
