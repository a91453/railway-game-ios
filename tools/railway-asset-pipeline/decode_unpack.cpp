// Railway asset archive decoder: purchaser-supplied BIN -> unpacked stream.
// Format/decompression adapted from Dasug/a9tools (MIT), copyright (c) 2022 Marius Kaufmann.
// See THIRD_PARTY_NOTICES.md. No input assets are embedded in this source.
//
// Usage: c++ -std=c++17 -O2 -Wall -Wextra decode_unpack.cpp -o /tmp/railway-decode
//        /tmp/railway-decode /private/path/vp.bin /private/output/vp.unpacked [max-output-MiB]
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <string>
#include <vector>

using Byte = std::uint8_t;
static constexpr Byte fixedKey[256] = {
    0x3b,0x16,0x6f,0xd8,0xac,0xb2,0x09,0xfc,0xb0,0x9d,0xa9,0x3a,0xdc,0xa1,0x3f,0xd2,
    0x45,0x17,0x11,0x03,0xfb,0x59,0x5e,0x21,0xd3,0x7a,0x41,0xe8,0x6a,0x34,0xd9,0x10,
    0x66,0x21,0xa7,0x21,0xff,0x2e,0x37,0x89,0xbf,0x4e,0x03,0xec,0x85,0x6b,0x94,0xbb,
    0xd0,0xa2,0xea,0x08,0x3a,0xaf,0x1e,0x99,0x43,0xa6,0x46,0x3b,0x50,0xe5,0x99,0x58,
    0xf4,0x46,0xd4,0xcc,0x6d,0x99,0xdc,0xf5,0x72,0x51,0xa4,0x09,0x2c,0x7d,0x51,0xad,
    0x82,0xfa,0x9c,0xc3,0x99,0xe7,0x78,0x83,0x9b,0x5a,0xf5,0xcd,0xb8,0x51,0x65,0xbd,
    0x6b,0xec,0xbd,0x81,0xff,0xd9,0x3e,0x67,0x51,0x0f,0x54,0x3a,0xd7,0xbf,0xbe,0xcf,
    0xe1,0x87,0xef,0xdb,0x1f,0xea,0xb4,0x07,0x64,0xfd,0x18,0x47,0xa9,0x62,0x85,0x67,
    0x55,0x7a,0x2b,0xe7,0xbc,0xd7,0xa5,0x08,0xe5,0xf0,0xda,0x27,0x90,0x19,0x22,0x4a,
    0x77,0xb2,0xab,0xf9,0xd5,0x9e,0x1a,0x4f,0x25,0xf7,0x75,0x50,0x2c,0xff,0x40,0x7d,
    0x39,0x5a,0xe6,0xa6,0xac,0x7b,0x5b,0x00,0xb5,0x5d,0x00,0x77,0x5e,0x73,0xc7,0x45,
    0xcc,0xe1,0x97,0xc4,0xc1,0xec,0xf2,0x80,0x66,0xaf,0xd5,0x91,0x48,0x10,0xdf,0x28,
    0xa0,0xf3,0xb6,0x67,0xd7,0xae,0xa7,0x76,0x49,0xbc,0x8c,0xd3,0x4a,0xb5,0xf3,0xe9,
    0x66,0x7d,0x7c,0xe5,0xed,0xbc,0x83,0xc5,0xb0,0x8f,0xff,0xb1,0x05,0x7e,0xaa,0x8f,
    0x11,0xad,0x63,0xd2,0x46,0x56,0xd0,0x92,0x2a,0x76,0x47,0xe2,0x5a,0xc7,0xef,0x5e,
    0xcf,0xef,0x22,0x03,0x61,0xf7,0x16,0x44,0x89,0xfe,0xbd,0x59,0x6b,0x2f,0xe9,0xdb
};
static std::uint32_t le32(const Byte* p) {
    return std::uint32_t(p[0]) | (std::uint32_t(p[1]) << 8)
         | (std::uint32_t(p[2]) << 16) | (std::uint32_t(p[3]) << 24);
}
int main(int argc, char** argv) {
    if (argc < 3 || argc > 4) {
        std::cerr << "Usage: railway-decode input.bin output.unpacked [max-output-MiB]\n";
        return 2;
    }
    std::size_t limit = 1024ULL * 1024ULL * 1024ULL;
    if (argc == 4) {
        char* end = nullptr;
        unsigned long long mib = std::strtoull(argv[3], &end, 10);
        if (!end || *end != '\0' || mib == 0 || mib > 4096) {
            std::cerr << "Invalid output limit (MiB).\n";
            return 2;
        }
        limit = static_cast<std::size_t>(mib) * 1024ULL * 1024ULL;
    }
    std::ifstream input(argv[1], std::ios::binary);
    if (!input) { std::cerr << "Cannot open source file.\n"; return 3; }
    std::vector<Byte> raw((std::istreambuf_iterator<char>(input)),
                           std::istreambuf_iterator<char>());
    if (raw.size() <= 16) {
        std::cerr << "Empty or unsupported source stream.\n"; return 3;
    }
    const std::size_t payloadLength = raw.size() - 16;
    std::vector<Byte> decoded(payloadLength);
    for (std::size_t i = 0; i < payloadLength; ++i) {
        decoded[i] = raw[i % 16] ^ Byte(Byte(raw[i + 16]) + fixedKey[i % 256]);
    }
    std::size_t pos = 0;
    std::uint32_t declared = payloadLength >= 4 ? le32(decoded.data()) : 0;
    // A subset of records contains a four-byte uncompressed-length prefix.
    const bool lengthPrefix = std::uint64_t(declared) > payloadLength
                           && std::uint64_t(declared) < std::uint64_t(payloadLength) * 16;
    if (lengthPrefix) pos = 4;
    Byte ring[4096] = {};
    std::size_t ringPos = 0xfee;
    unsigned int flags = 0;
    std::vector<Byte> output;
    output.reserve(std::min(limit, payloadLength * std::size_t(2)));
    auto emit = [&](Byte value) -> bool {
        if (output.size() >= limit) return false;
        output.push_back(value);
        ring[ringPos] = value;
        ringPos = (ringPos + 1) & 0xfff;
        return true;
    };
    while (pos < decoded.size()) {
        if ((flags & 0x100) == 0) flags = 0xff00 | decoded[pos++];
        if ((flags & 1) == 0) {
            if (pos + 1 >= decoded.size()) break;
            const unsigned int first = decoded[pos++];
            const unsigned int second = decoded[pos++];
            const unsigned int start = first | ((second & 0xf0) << 4);
            const unsigned int count = (second & 0x0f) + 3;
            for (unsigned int k = 0; k < count; ++k) {
                if (!emit(ring[(start + k) & 0xfff])) {
                    std::cerr << "Output exceeded safety limit.\n"; return 4;
                }
            }
        } else {
            if (pos >= decoded.size()) break;
            if (!emit(decoded[pos++])) {
                std::cerr << "Output exceeded safety limit.\n"; return 4;
            }
        }
        flags >>= 1;
    }
    if (output.empty()) { std::cerr << "No bytes decoded.\n"; return 4; }
    std::ofstream dest(argv[2], std::ios::binary | std::ios::trunc);
    if (!dest) { std::cerr << "Cannot create destination.\n"; return 5; }
    dest.write(reinterpret_cast<const char*>(output.data()), output.size());
    if (!dest) { std::cerr << "Write failed.\n"; return 5; }
    std::cout << "input_bytes=" << raw.size() << " unpacked_bytes=" << output.size()
              << " length_prefix=" << (lengthPrefix ? "yes" : "no") << "\n";
}
