// The base map's tiles are gzipped (decision 234): the 3D map reads them
// itself, on every platform the package builds on, so the inflate is here
// in Swift rather than in Apple's Compression framework.
//
// Ported from puff.c 2.3 (contrib/puff in zlib, https://github.com/madler/zlib),
// a simple inflate that specifies the deflate format (RFC 1951). Altered
// from the original: translated to Swift, output grown as needed, and a
// gzip member's header and trailer read round it (RFC 1952). Its notice:
//
//   Copyright (C) 2002-2013 Mark Adler, all rights reserved
//   version 2.3, 21 Jan 2013
//
//   This software is provided 'as-is', without any express or implied
//   warranty.  In no event will the author be held liable for any damages
//   arising from the use of this software.
//
//   Permission is granted to anyone to use this software for any purpose,
//   including commercial applications, and to alter it and redistribute it
//   freely, subject to the following restrictions:
//
//   1. The origin of this software must not be misrepresented; you must not
//      claim that you wrote the original software. If you use this software
//      in a product, an acknowledgment in the product documentation would be
//      appreciated but is not required.
//   2. Altered source versions must be plainly marked as such, and must not be
//      misrepresented as being the original software.
//   3. This notice may not be removed or altered from any source distribution.
//
//   Mark Adler    madler@alumni.caltech.edu

/// Unpacks deflate and gzip data.
enum Inflate {
    enum Failure: Error, Equatable {
        /// The data ends before its last block does.
        case truncated
        /// The data is not deflate, or not gzip, as it says it is.
        case malformed
    }

    /// The bytes of the gzip member `data` (RFC 1952) holds: its header
    /// skipped, its deflate data unpacked.
    static func gunzip(_ data: [UInt8]) throws(Failure) -> [UInt8] {
        // ID1 ID2 CM FLG, MTIME (4), XFL, OS.
        guard data.count >= 18, data[0] == 0x1F, data[1] == 0x8B, data[2] == 8 else { throw .malformed }
        let flags = data[3]
        var at = 10
        if flags & 4 != 0 {  // FEXTRA
            guard at + 2 <= data.count else { throw .truncated }
            at += 2 + (Int(data[at]) | Int(data[at + 1]) << 8)
        }
        for flag: UInt8 in [8, 16] where flags & flag != 0 {  // FNAME, FCOMMENT: ending in a zero
            while at < data.count, data[at] != 0 { at += 1 }
            at += 1
        }
        if flags & 2 != 0 { at += 2 }  // FHCRC
        guard at <= data.count else { throw .truncated }
        return try inflate(data[at...])
    }

    /// The bytes the deflate data `data` packs (RFC 1951).
    static func inflate(_ data: ArraySlice<UInt8>) throws(Failure) -> [UInt8] {
        var state = State(input: data)
        try state.run()
        return state.output
    }

    /// The longest code, and the number of length and distance codes.
    private static let maximumBits = 15
    private static let lengthCodes = 286, distanceCodes = 30
    private static let fixedLengthCodes = 288

    /// Lengths and extra bits of length codes 257…285, and of distance
    /// codes 0…29.
    private static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                                            35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                                             3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                                              257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                                              8193, 12289, 16385, 24577]
    private static let distanceExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                                               7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    /// The order the code length code lengths come in.
    private static let order: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    /// A canonical Huffman code: how many codes there are of each length,
    /// and the symbols in code order.
    private struct Huffman {
        var count = [Int](repeating: 0, count: Inflate.maximumBits + 1)
        var symbol: [Int]

        /// The code of the `lengths` of each symbol; `left` is negative when
        /// the lengths are over-subscribed, positive when incomplete.
        init(lengths: ArraySlice<Int>, left: inout Int) {
            symbol = [Int](repeating: 0, count: lengths.count)
            for length in lengths { count[length] += 1 }
            left = 1
            guard count[0] != lengths.count else { left = 0; return }
            for length in 1...Inflate.maximumBits {
                left <<= 1
                left -= count[length]
                if left < 0 { return }
            }
            var offsets = [Int](repeating: 0, count: Inflate.maximumBits + 1)
            for length in 1..<Inflate.maximumBits { offsets[length + 1] = offsets[length] + count[length] }
            for (index, length) in lengths.enumerated() where length != 0 {
                symbol[offsets[length]] = index
                offsets[length] += 1
            }
        }
    }

    private struct State {
        let input: ArraySlice<UInt8>
        var at: Int
        var bitBuffer = 0, bitCount = 0
        var output: [UInt8] = []

        init(input: ArraySlice<UInt8>) {
            self.input = input
            at = input.startIndex
            output.reserveCapacity(input.count * 4)
        }

        mutating func bits(_ need: Int) throws(Failure) -> Int {
            var value = bitBuffer
            while bitCount < need {
                guard at < input.endIndex else { throw .truncated }
                value |= Int(input[at]) << bitCount
                at += 1
                bitCount += 8
            }
            bitBuffer = value >> need
            bitCount -= need
            return value & ((1 << need) - 1)
        }

        mutating func run() throws(Failure) {
            var last = 0
            repeat {
                last = try bits(1)
                switch try bits(2) {
                case 0: try stored()
                case 1: try fixed()
                case 2: try dynamic()
                default: throw .malformed
                }
            } while last == 0
        }

        mutating func stored() throws(Failure) {
            bitBuffer = 0
            bitCount = 0
            guard at + 4 <= input.endIndex else { throw .truncated }
            let length = Int(input[at]) | Int(input[at + 1]) << 8
            let complement = Int(input[at + 2]) | Int(input[at + 3]) << 8
            guard length == ~complement & 0xFFFF else { throw .malformed }
            at += 4
            guard at + length <= input.endIndex else { throw .truncated }
            output.append(contentsOf: input[at..<(at + length)])
            at += length
        }

        mutating func decode(_ code: Huffman) throws(Failure) -> Int {
            var value = 0, first = 0, index = 0
            for length in 1...Inflate.maximumBits {
                value |= try bits(1)
                let count = code.count[length]
                if value - count < first { return code.symbol[index + (value - first)] }
                index += count
                first += count
                first <<= 1
                value <<= 1
            }
            throw .malformed
        }

        mutating func codes(lengths: Huffman, distances: Huffman) throws(Failure) {
            while true {
                var symbol = try decode(lengths)
                if symbol < 256 {
                    output.append(UInt8(symbol))
                } else if symbol == 256 {
                    return
                } else {
                    symbol -= 257
                    guard symbol < 29 else { throw .malformed }
                    let length = Inflate.lengthBase[symbol] + (try bits(Inflate.lengthExtra[symbol]))
                    let code = try decode(distances)
                    guard code < 30 else { throw .malformed }
                    let distance = Inflate.distanceBase[code] + (try bits(Inflate.distanceExtra[code]))
                    guard distance <= output.count else { throw .malformed }
                    let from = output.count - distance
                    for step in 0..<length { output.append(output[from + step]) }
                }
            }
        }

        mutating func fixed() throws(Failure) {
            var lengths = [Int](repeating: 0, count: Inflate.fixedLengthCodes)
            for symbol in 0..<Inflate.fixedLengthCodes {
                lengths[symbol] = symbol < 144 ? 8 : symbol < 256 ? 9 : symbol < 280 ? 7 : 8
            }
            var left = 0
            let lengthCode = Huffman(lengths: lengths[...], left: &left)
            let distanceCode = Huffman(lengths: [Int](repeating: 5, count: Inflate.distanceCodes)[...], left: &left)
            try codes(lengths: lengthCode, distances: distanceCode)
        }

        mutating func dynamic() throws(Failure) {
            let lengthCount = try bits(5) + 257, distanceCount = try bits(5) + 1, codeCount = try bits(4) + 4
            guard lengthCount <= Inflate.lengthCodes, distanceCount <= Inflate.distanceCodes else { throw .malformed }
            var lengths = [Int](repeating: 0, count: Inflate.lengthCodes + Inflate.distanceCodes)
            for index in 0..<codeCount { lengths[Inflate.order[index]] = try bits(3) }
            var left = 0
            let codeLengths = Huffman(lengths: lengths[0..<19], left: &left)
            guard left == 0 else { throw .malformed }
            var index = 0
            while index < lengthCount + distanceCount {
                var symbol = try decode(codeLengths)
                if symbol < 16 {
                    lengths[index] = symbol
                    index += 1
                } else {
                    var length = 0
                    if symbol == 16 {
                        guard index > 0 else { throw .malformed }
                        length = lengths[index - 1]
                        symbol = 3 + (try bits(2))
                    } else if symbol == 17 {
                        symbol = 3 + (try bits(3))
                    } else {
                        symbol = 11 + (try bits(7))
                    }
                    guard index + symbol <= lengthCount + distanceCount else { throw .malformed }
                    for _ in 0..<symbol {
                        lengths[index] = length
                        index += 1
                    }
                }
            }
            guard lengths[256] != 0 else { throw .malformed }
            let lengthCode = Huffman(lengths: lengths[0..<lengthCount], left: &left)
            // An incomplete code is allowed only for a single code of length 1.
            guard left == 0 || (left > 0 && lengthCount == lengthCode.count[0] + lengthCode.count[1]) else { throw .malformed }
            let distanceCode = Huffman(lengths: lengths[lengthCount..<(lengthCount + distanceCount)], left: &left)
            guard left == 0 || (left > 0 && distanceCount == distanceCode.count[0] + distanceCode.count[1]) else { throw .malformed }
            try codes(lengths: lengthCode, distances: distanceCode)
        }
    }
}
