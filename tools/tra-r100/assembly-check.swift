// Independent M3DM v1 / M3DAssembly v1 verifier. No GamePresentation or JS code.
// swift tools/tra-r100/assembly-check.swift OUT SPEC.json
import Foundation
import CoreFoundation

struct AuditFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw AuditFailure(message) }
}

func object(_ data: Data, _ name: String) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AuditFailure("\(name): expected JSON object")
    }
    return value
}

func canonical(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
}

func number(_ value: Any?, _ name: String) throws -> Double {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else {
        throw AuditFailure("\(name): expected finite number")
    }
    return n.doubleValue
}

func word(_ bytes: [UInt8], _ at: Int) -> UInt32 {
    UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 |
        UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
}

func halfWord(_ bytes: [UInt8], _ at: Int) -> UInt16 {
    UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
}

func putWord(_ value: UInt32, _ bytes: inout [UInt8], _ at: Int) {
    for byte in 0..<4 { bytes[at + byte] = UInt8(truncatingIfNeeded: value >> UInt32(byte * 8)) }
}

func sha256(_ file: URL) throws -> String {
    let task = Process(), pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sha256sum")
    task.arguments = [file.path]
    task.standardOutput = pipe
    task.standardError = Pipe()
    try task.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0,
          let line = String(data: output, encoding: .utf8),
          let digest = line.split(separator: " ").first, digest.count == 64 else {
        throw AuditFailure("SHA256 failed for \(file.lastPathComponent)")
    }
    return String(digest)
}

struct NativeUnit {
    let bytes: Data
    let payload: [UInt8]
    let triangles: Int

    init(_ data: Data, named name: String) throws {
        let bytes = [UInt8](data)
        try require(bytes.count >= 16, "\(name): short M3DM header")
        try require(Array(bytes[0..<4]) == Array("M3DM".utf8), "\(name): wrong M3DM magic")
        try require(halfWord(bytes, 4) == 1 && halfWord(bytes, 6) == 0, "\(name): unsupported M3DM version")
        let count = Int(word(bytes, 8)), metadataLength = Int(word(bytes, 12))
        try require(count > 0 && count <= 15_000, "\(name): illegal independent unit triangle count")
        let start = 16 + ((metadataLength + 3) / 4) * 4
        try require(start <= bytes.count && bytes.count == start + count * 52, "\(name): wrong M3DM length")
        try require(metadataLength > 0, "\(name): missing provenance")
        let metadata = Data(bytes[16..<(16 + metadataLength)])
        guard let text = String(data: metadata, encoding: .utf8), !text.allSatisfy(\.isWhitespace) else {
            throw AuditFailure("\(name): invalid provenance UTF-8")
        }
        _ = try JSONSerialization.jsonObject(with: metadata)
        self.bytes = data
        self.payload = Array(bytes[start...])
        self.triangles = count
        _ = try inspectPayload(payload, named: name)
    }
}

struct Placement {
    let unit: String
    let translation: [Float]
    let reversed: Bool

    init(_ value: [String: Any], named name: String) throws {
        guard let unit = value["unit"] as? String, !unit.isEmpty,
              let rawTranslation = value["translation"] as? [Any], rawTranslation.count == 3 else {
            throw AuditFailure("\(name): invalid unit or translation")
        }
        let translation = try rawTranslation.enumerated().map { axis, value in
            Float(try number(value, "\(name).translation[\(axis)]"))
        }
        try require(translation.allSatisfy(\.isFinite), "\(name): translation outside Float32 range")
        let angle = try number(value["rotation_degrees"] ?? NSNumber(value: 0), "\(name).rotation_degrees")
        try require(angle == 0 || angle == 180, "\(name): only explicit 0/180-degree rotation is supported")
        if let scale = value["scale_x"] {
            try require(try number(scale, "\(name).scale_x") == 1, "\(name): scaling violates the assembly contract")
        }
        self.unit = unit
        self.translation = translation
        self.reversed = angle == 180
    }
}

struct PayloadInspection {
    let minimum: [Float]
    let maximum: [Float]
    let allVertexFieldsFNV64: String
}

// M3DM stores positions, RGBA and the three native material flags. Normals
// and the layer are derived independently here from the final Float32 triangle.
func inspectPayload(_ bytes: [UInt8], named name: String) throws -> PayloadInspection {
    try require(!bytes.isEmpty && bytes.count % 52 == 0, "\(name): malformed triangle payload")
    var low = [Float](repeating: .infinity, count: 3)
    var high = [Float](repeating: -.infinity, count: 3)
    var hash: UInt64 = 14_695_981_039_346_656_037
    func hashWord(_ value: UInt32) {
        for byte in 0..<4 {
            hash = (hash ^ UInt64(UInt8(truncatingIfNeeded: value >> UInt32(byte * 8)))) &* 1_099_511_628_211
        }
    }
    for base in stride(from: 0, to: bytes.count, by: 52) {
        let flags = word(bytes, base)
        try require(flags & ~UInt32(7) == 0 && !(flags & 2 != 0 && flags & 4 != 0), "\(name): invalid native flags")
        var corners: [[Float]] = []
        for corner in 0..<3 {
            let p = (0..<3).map { Float(bitPattern: word(bytes, base + 4 + corner * 16 + $0 * 4)) }
            try require(p.allSatisfy(\.isFinite), "\(name): nonfinite vertex")
            corners.append(p)
            for axis in 0..<3 {
                low[axis] = min(low[axis], p[axis]); high[axis] = max(high[axis], p[axis])
            }
        }
        let u = zip(corners[1], corners[0]).map(-)
        let v = zip(corners[2], corners[0]).map(-)
        let cross = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        let length = (cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]).squareRoot()
        try require(length.isFinite && length > 0, "\(name): degenerate or invalid triangle")
        let normal = cross.map { $0 / length }
        for corner in 0..<3 {
            for axis in 0..<3 { hashWord(corners[corner][axis].bitPattern) }
            for value in normal { hashWord(value.bitPattern) }
            hashWord(word(bytes, base + 4 + corner * 16 + 12))
            // All flag bits determine the native layer; retain all three.
            hashWord(flags)
        }
    }
    return PayloadInspection(minimum: low, maximum: high, allVertexFieldsFNV64: String(format: "%016llx", hash))
}

func expand(_ rows: [[String: Any]], units: [String: NativeUnit]) throws -> [UInt8] {
    var output: [UInt8] = []
    for (index, row) in rows.enumerated() {
        let p = try Placement(row, named: "placement[\(index)]")
        guard let source = units[p.unit] else { throw AuditFailure("Missing independent unit \(p.unit)") }
        var transformed = source.payload
        let sign: Float = p.reversed ? -1 : 1
        for triangle in 0..<source.triangles {
            for corner in 0..<3 {
                for axis in 0..<3 {
                    let at = triangle * 52 + 4 + corner * 16 + axis * 4
                    let value = Float(bitPattern: word(source.payload, at))
                    let scaled: Float = value * (axis == 2 ? 1 : sign)
                    let translated: Float = scaled + p.translation[axis]
                    try require(translated.isFinite, "Assembly transform produced a nonfinite vertex")
                    putWord(translated.bitPattern, &transformed, at)
                }
            }
        }
        output.append(contentsOf: transformed)
    }
    return output
}

func rows(_ value: Any?, _ name: String) throws -> [[String: Any]] {
    guard let rows = value as? [[String: Any]], !rows.isEmpty else {
        throw AuditFailure("\(name): missing nonempty placements")
    }
    return rows
}

func safeFile(_ root: URL, _ path: String) throws -> URL {
    let file = root.appendingPathComponent(path).standardizedFileURL
    try require(!path.hasPrefix("/") && file.path.hasPrefix(root.path + "/"), "Manifest path escapes output directory")
    return file
}

func verify(root: URL, specURL: URL) throws -> [String: Any] {
    let spec = try object(Data(contentsOf: specURL), "configuration")
    let manifestURL = root.appendingPathComponent("manifest.json")
    let manifest = try object(Data(contentsOf: manifestURL), "manifest")
    guard let records = manifest["models"] as? [[String: Any]] else { throw AuditFailure("Missing manifest models") }
    var byID: [String: [String: Any]] = [:]
    for record in records {
        guard let id = record["id"] as? String, byID[id] == nil else { throw AuditFailure("Missing or duplicate manifest ID") }
        byID[id] = record
    }
    let specs = spec["assemblies"] as? [[String: Any]] ?? []
    let assemblyRecords = records.filter { ($0["native_kind"] as? String) == "assembly" }
    if specs.isEmpty {
        try require(assemblyRecords.isEmpty, "Manifest contains assemblies absent from configuration")
        return ["state": "UNVERIFIED", "reason": "Configuration supplies no assemblies; no complete formation is claimed.",
                "configuration_sha256": try sha256(specURL), "assemblies": []]
    }
    let specIDs = specs.compactMap { $0["id"] as? String }
    try require(specIDs.count == specs.count && Set(specIDs).count == specIDs.count, "Missing or duplicate configured assembly ID")
    try require(Set(specIDs) == Set(assemblyRecords.compactMap { $0["id"] as? String }), "Manifest/configuration assembly inventories differ")
    var reports: [[String: Any]] = []
    var testedFaults = Set<String>()
    for item in specs {
        let id = item["id"] as! String
        guard let record = byID[id], let nativePath = record["native"] as? String,
              let payloadPath = record["assembly_payload"] as? String else {
            throw AuditFailure("\(id): missing assembly native/payload manifest paths")
        }
        let nativeURL = try safeFile(root, nativePath), payloadURL = try safeFile(root, payloadPath)
        let scene = try object(Data(contentsOf: nativeURL), id)
        try require(scene["format"] as? String == "M3DAssembly", "\(id): wrong assembly format")
        try require(try number(scene["version"], "\(id).version") == 1, "\(id): unsupported assembly version")
        let configured = try rows(item["placements"], "\(id) configuration")
        let placements = try rows(scene["placements"], "\(id) native")
        try require(try canonical(configured) == canonical(placements), "\(id): native placements/order differ from configuration")
        guard let embedded = scene["units"] as? [String: String] else { throw AuditFailure("\(id): invalid embedded units") }
        let used = try Set(placements.enumerated().map { try Placement($0.element, named: "placement[\($0.offset)]").unit })
        try require(used == Set(embedded.keys), "\(id): missing or unused embedded unit")
        var units: [String: NativeUnit] = [:], unitReports: [[String: Any]] = []
        for unitID in used.sorted() {
            guard let source = byID[unitID], source["native_kind"] as? String != "assembly",
                  let path = source["native"] as? String, let base64 = embedded[unitID],
                  let bytes = Data(base64Encoded: base64), bytes.base64EncodedString() == base64 else {
                throw AuditFailure("\(id): invalid independent unit reference \(unitID)")
            }
            let file = try safeFile(root, path), original = try Data(contentsOf: file)
            try require(bytes == original, "\(id): embedded \(unitID) is not the final independent unit bytes")
            units[unitID] = try NativeUnit(bytes, named: unitID)
            unitReports.append(["id": unitID, "native": path, "sha256": try sha256(file), "bytes": bytes.count])
        }
        // Expand actual M3DA placements, after verifying them against the fixed
        // configuration. This never substitutes a hard-coded train formation.
        let actualExpansion = try expand(placements, units: units)
        let expectedExpansion = try expand(configured, units: units)
        try require(actualExpansion == expectedExpansion, "\(id): native/configuration expansion differs")
        let payload = [UInt8](try Data(contentsOf: payloadURL))
        try require(actualExpansion == payload, "\(id): independent Swift expansion differs from delivered triangle payload")
        let inspection = try inspectPayload(payload, named: id)
        if let count = record["triangles"] {
            try require(try number(count, "\(id).triangles") == Double(payload.count / 52), "\(id): manifest triangle count differs")
        }
        for (key, actual) in [("minimum", inspection.minimum), ("maximum", inspection.maximum)] {
            if let values = record[key] as? [Any] {
                try require(values.count == 3, "\(id): malformed manifest bounds")
                for axis in 0..<3 {
                    try require(Float(try number(values[axis], "\(id).\(key)")) == actual[axis], "\(id): manifest \(key) differs")
                }
            }
        }
        var faults: [[String: Any]] = []
        func rejectTransform(_ name: String, mutated: [[String: Any]]) throws {
            let configurationRejects = try canonical(mutated) != canonical(configured)
            let wrongPayload = try expand(mutated, units: units)
            let payloadRejects = wrongPayload != payload
            try require(configurationRejects && payloadRejects, "\(id): verifier failed to reject actual \(name) fault")
            faults.append(["fault": name, "state": "VERIFIED", "configuration_rejected": true,
                           "payload_rejected": true, "mutated_payload_bytes": wrongPayload.count])
            testedFaults.insert(name)
        }
        if placements.count > 1,
           let different = try (1..<placements.count).first(where: { try canonical(placements[$0]) != canonical(placements[0]) }) {
            var wrong = placements; wrong.swapAt(0, different)
            try rejectTransform("wrong_order", mutated: wrong)
        } else {
            faults.append(["fault": "wrong_order", "state": "UNVERIFIED", "reason": "No distinct pair of placements in this assembly."])
        }
        var reversed = placements
        let original = try Placement(reversed[0], named: "fault target")
        reversed[0]["rotation_degrees"] = original.reversed ? 0 : 180
        try rejectTransform("wrong_direction", mutated: reversed)
        if let index = try placements.indices.first(where: { try Placement(placements[$0], named: "fault target").reversed }) {
            var doubled = placements
            doubled[index]["rotation_degrees"] = 0 // intended 180, erroneously rotated a second 180
            try rejectTransform("double_reversal", mutated: doubled)
        } else {
            faults.append(["fault": "double_reversal", "state": "UNVERIFIED", "reason": "This configuration has no intended 180-degree placement; no double-reversal claim."])
        }
        var displaced = placements
        var translation = displaced[0]["translation"] as! [Any]
        translation[0] = Double(original.translation[0]) + 0.75
        displaced[0]["translation"] = translation
        try rejectTransform("wrong_translation", mutated: displaced)
        // Mutate one actual referenced unit's stored RGBA. The unit-reference
        // bytes check and full payload comparison must both reject this fault.
        let unitID = used.sorted()[0], unit = units[unitID]!
        var corruptBytes = [UInt8](unit.bytes)
        let payloadStart = 16 + ((Int(word(corruptBytes, 12)) + 3) / 4) * 4
        corruptBytes[payloadStart + 16] ^= 1
        let corrupt = try NativeUnit(Data(corruptBytes), named: "corrupt reference fault")
        var corruptUnits = units; corruptUnits[unitID] = corrupt
        try require(Data(corruptBytes) != unit.bytes && (try expand(placements, units: corruptUnits)) != payload,
                    "\(id): corrupt unit reference was not rejected")
        faults.append(["fault": "different_embedded_unit_bytes", "state": "VERIFIED",
                       "reference_bytes_rejected": true, "payload_rejected": true])
        testedFaults.insert("different_embedded_unit_bytes")
        reports.append(["id": id, "state": "VERIFIED", "placements": placements.count,
                        "triangles": payload.count / 52, "vertices": payload.count / 52 * 3,
                        "minimum": inspection.minimum, "maximum": inspection.maximum,
                        "native": nativePath, "native_sha256": try sha256(nativeURL),
                        "assembly_payload": payloadPath, "payload_sha256": try sha256(payloadURL),
                        "all_vertex_fields_fnv64": inspection.allVertexFieldsFNV64,
                        "payload_bytes_equal": true, "configured_placements_equal": true,
                        "embedded_unit_bytes_equal": true, "units": unitReports, "faults": faults])
    }
    return ["state": "VERIFIED", "implementation": "Independent Foundation-only Swift; no JS or GamePresentation imports.",
            "configuration_sha256": try sha256(specURL), "manifest_sha256": try sha256(manifestURL),
            "arithmetic": "Float32 multiplication then Float32 addition; native Z-up, yaw 0/180 degrees only; no scale.",
            "stored_fields": "Every triangle flag and every corner Float32 XYZ / UInt32 RGBA compared byte-for-byte; derived Float32 normals and native material flags included in all-vertex FNV64.",
            "limits": "Static configuration/native/payload verification only; does not establish real-world formation evidence, coupler compatibility, runtime selection or device validation.",
            "faults_tested": testedFaults.sorted(), "assemblies": reports]
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift tools/tra-r100/assembly-check.swift OUT SPEC.json\n".utf8))
    exit(2)
}
let outputRoot = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let specURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
let reportURL = outputRoot.appendingPathComponent("swift-assembly-verification.json")
do {
    let report = try verify(root: outputRoot, specURL: specURL)
    var bytes = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    bytes.append(10)
    try bytes.write(to: reportURL)
    print("\(report["state"] as! String): Swift assembly verification -> \(reportURL.lastPathComponent)")
} catch {
    let report: [String: Any] = ["state": "FAILED", "error": String(describing: error)]
    if let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
        try? bytes.write(to: reportURL)
    }
    FileHandle.standardError.write(Data("Swift assembly verification FAILED: \(error)\n".utf8))
    exit(1)
}
