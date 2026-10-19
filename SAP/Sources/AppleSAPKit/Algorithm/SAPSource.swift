// Copyright (c) 2026 ApplePackage contributors.

/// Address-independent expansion of the session's 576 logical source bytes.
struct SAPSource: Sendable {
    var material: [UInt8]
    var auxiliaryWords0: [UInt32]
    var auxiliaryWords1: [UInt32]
    var cache2: [UInt8]
    var cache3: [UInt8]
    var projectionMask: UInt32
    var selectors: [UInt8]
    var initialCache: [UInt32]
    var terminalCache: [UInt32]

    static func prepare(_ source: [UInt8]) throws -> SAPSource {
        guard source.count == 576 else {
            throw SAPError.invalidInput("Expected 576 logical source bytes")
        }
        let schedule = makeSchedule(source)
        let tables = try makeTables(source)
        let auxiliary = makeAuxiliary(tables)
        let caches = makeCoefficientCaches(source, tables: tables, schedule: schedule)
        return SAPSource(
            material: makeMaterial(source, schedule: schedule),
            auxiliaryWords0: auxiliary.0, auxiliaryWords1: auxiliary.1,
            cache2: auxiliary.2, cache3: auxiliary.3, projectionMask: ~tables.mask,
            selectors: schedule.selectors, initialCache: caches.0, terminalCache: caches.1
        )
    }

    private struct Schedule {
        let lengths: [[Int]]
        let selectors: [UInt8]
    }

    private struct SourceTables {
        let words: [UInt32]
        let cache: [UInt8]
        let mask: UInt32
        let seeds: [UInt32]
    }

    private static func makeSchedule(_ source: [UInt8]) -> Schedule {
        var lengths = [[Int]](repeating: [Int](repeating: 0, count: 11), count: 16)
        for column in 0 ..< 11 {
            let bank = [0xe0, 0xf0, 0xc0][column / 4]
            let moduli = [[7, 27, 47, 77], [9, 29, 49, 79], [5, 25, 45, 75]][column / 4]
            for group in 0 ..< 4 {
                let at = 4 * (column % 4) + group
                let value = Int(source[0x30 + at] ^ source[bank + at])
                for lane in 0 ..< 4 {
                    let digit = (value % moduli[lane]) & 3
                    lengths[4 * group + lane][column] = [3, 3, 5, 1][digit]
                }
            }
            var cost = lengths.reduce(0) { $0 + $1[column] }
            var row = Int(source[0x31] ^ source[0xc1]) & 15
            while cost > 32 {
                cost -= lengths[row][column] - 1
                lengths[row][column] = 1
                row = (row + 5) & 15
            }
        }
        var selectors: [UInt8] = []
        for index in 0 ..< 8 {
            let value = Int(source[0xe0 + index] ^ source[0xf0 + index])
            selectors.append(UInt8(value % 7))
            selectors.append(UInt8((value / 7) % 7))
        }
        return Schedule(lengths: lengths, selectors: selectors)
    }

    private static func makeTables(_ source: [UInt8]) throws -> SourceTables {
        let size = (Int(source[0xfa] ^ source[0xca]) << 8) | Int(source[0xf3] ^ source[0xc3])
        guard size > 0 else {
            throw SAPError.invalidInput("Source inverse cache must not be empty")
        }
        let pairs = [(0xea, 0xfa), (0xe4, 0xf4), (0xed, 0xfd), (0xe6, 0xf6)]
        var seed: UInt32 = 0
        for (a, b) in pairs {
            seed = (seed << 8) | UInt32(source[a] ^ source[b])
        }
        var state = seed
        var states: [UInt32] = []
        for _ in 0 ..< 13 {
            let wide = UInt64(state)
            state = UInt32(((wide &* wide) &+ 1) % 0xfffffffb)
            states.append(state)
        }
        var mask: UInt32 = 1 << Int(seed & 7)
        for lane in 1 ..< 4 {
            mask |= 1 << (8 * lane + Int(states[lane - 1] & 7))
        }
        let basis = Array(states[3 ..< 11])
        let header = states[11]
        state = states[12]
        var cache: [UInt8] = (0 ..< size).map { index in
            source[(index + 3 * Int(source[index % 576]) + 2) % 576] ^ 0xd6
        }
        var words: [UInt32] = []
        for index in 0 ..< 256 {
            var word = header ^ (state & mask)
            for bit in 0 ..< 8 where index & (1 << bit) != 0 {
                word ^= basis[bit]
            }
            words.append(word)
            cache[Int((word & ~mask) % UInt32(size))] = UInt8(index) ^ 0xd6
            let value = state ^ 0x63
            // The original signed widening contributes residue512 modulo576.
            let correction = index != 0 && state & 0x80000000 != 0 ? 512 : 0
            let position = (17 * Int(value >> 4) + 3 * Int(value & 15) + 176 + correction) % 576
            state = 0
            for byte in 0 ..< 4 {
                state |= UInt32(source[(position + byte) % 576]) << (8 * byte)
            }
        }
        return SourceTables(words: words, cache: cache, mask: mask, seeds: Array(states[3 ..< 12]))
    }

    private static func makeAuxiliary(_ tables: SourceTables) -> ([UInt32], [UInt32], [UInt8], [UInt8]) {
        let index0: [UInt8] = [0x3c, 0x44, 0x73, 0xcc, 0x50, 0xba, 0x9e, 0xee]
        let index1: [UInt8] = [0x9f, 0x72, 0xe1, 0x3b, 0xdd, 0x31, 0x24, 0x8f]
        let map2: [UInt8] = [0xe3, 0x34, 0xda, 0x73, 0xb4, 0xa0, 0x4f, 0x2b]
        let map3: [UInt8] = [0x1f, 0x35, 0x3b, 0xf7, 0xd9, 0xad, 0xd4, 0x93]
        var words0 = [UInt32](repeating: 0, count: 256)
        var words1 = words0
        for (index, word) in tables.words.enumerated() {
            words0[Int(linearByte(UInt8(index), basis: index0))] = word ^ 0xd90b5d96
            words1[Int(linearByte(UInt8(index), basis: index1))] = word ^ 0xaa8095ee
        }
        let cache2 = tables.cache.map { linearByte($0, basis: map2, constant: 0xc0) }
        let cache3 = tables.cache.enumerated().map { index, value in
            linearByte(value, basis: map3, constant: 0x47) ^ UInt8((index >> 2) & 255)
        }
        return (words0, words1, cache2, cache3)
    }

    private static func linearByte(_ value: UInt8, basis: [UInt8], constant: UInt8 = 0) -> UInt8 {
        var result = constant
        for bit in 0 ..< 8 where value & (1 << bit) != 0 {
            result ^= basis[bit]
        }
        return result
    }

    private static func makeCoefficientCaches(
        _ source: [UInt8], tables: SourceTables, schedule: Schedule
    ) -> ([UInt32], [UInt32]) {
        var caches: [[UInt32]] = []
        let descriptions: [(Int, Int, [Int], UInt32)] = [
            (10, 0x1a0, SAPParameters.initialOrder, tables.seeds[8] ^ 0xe62818fc),
            (0, 0x40, SAPParameters.terminalOrder, 0xaf615514),
        ]
        for (column, base, order, bias) in descriptions {
            var result = [UInt32](repeating: 0, count: 16)
            var position = 0
            for (row, slot) in order.enumerated() {
                let length = schedule.lengths[row][column]
                if length != 1 {
                    let key = operandKey(source, row: row, position: position, length: length, base: base, column: column)
                    result[slot] = tables.words[key] ^ bias
                }
                position += length
            }
            caches.append(result)
        }
        return (caches[0], caches[1])
    }

    private static func operandKey(
        _ source: [UInt8], row: Int, position: Int, length: Int, base: Int, column: Int
    ) -> Int {
        var key: UInt8 = 0
        for byte in 0 ..< length {
            key ^= source[base + position + byte]
                ^ padColumns[column][(position + byte) % 16] ^ padRows[column][row]
        }
        return Int(key)
    }

    private static func makeMaterial(_ source: [UInt8], schedule: Schedule) -> [UInt8] {
        var material = [UInt8](repeating: 0, count: 576)
        let copies = [
            (0x20, 0xf0), (0x70, 0xe0), (0x120, 0xd0), (0x130, 0x220),
            (0x140, 0x110), (0x150, 0x100), (0x160, 0x80), (0x170, 0x120),
            (0x180, 0x20), (0x190, 0x90), (0x1a0, 0x190), (0x1b0, 0x230),
            (0x1e0, 0xc0), (0x1f0, 0x30),
        ]
        for (destination, origin) in copies {
            material.replaceSubrange(destination ..< destination + 16, with: source[origin ..< origin + 16])
        }
        let descriptions = [
            (1, 0xa0, 0x200), (2, 0x200, 0x1c0), (3, 0x60, 0xc0),
            (4, 0, 0), (5, 0x1c0, 0x50), (6, 0x130, 0x80),
            (7, 0x1e0, 0xa0), (8, 0x170, 0x30), (9, 0x150, 0x100),
        ]
        let offsets = [2, 12, 6, 16, 0, 8, 22, 28, 4, 26, 18, 10, 20, 30, 24, 14]
        var walk = 0
        for (column, base, destination) in descriptions {
            var position = 0
            for row in 0 ..< 16 {
                let length = schedule.lengths[row][column]
                let key = operandKey(source, row: row, position: position, length: length, base: base, column: column)
                walk = (walk + base + position) % 576
                var first = Int(source[walk])
                walk = (walk + base + position + 1) % 576
                first = (first + Int(source[walk])) & 255
                let at = destination + offsets[row]
                material[at] = UInt8(first)
                material[at + 1] = UInt8((key - first) & 255)
                position += length
            }
        }
        // These 64 bytes had no native writer and no algorithm consumer.
        // The address-independent representation normalizes the padding to zero.
        return material
    }

    // Fixed row/column pad factors recovered from the pinned static data image.
    private static let padColumns: [[UInt8]] = [
        [0x00, 0x2e, 0x79, 0x60, 0xa4, 0x12, 0x40, 0xad, 0x22, 0xd5, 0xaf, 0x42, 0xb1, 0x49, 0x7b, 0x0e],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9e, 0xd7, 0xfe, 0x6f, 0x93, 0xda, 0x38, 0x6e, 0xc0, 0xfb],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9e, 0xd7, 0xfe, 0x6f, 0x93, 0xda, 0x38, 0x6e, 0xc0, 0xfb],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9e, 0xd7, 0xfe, 0x6f, 0x93, 0xda, 0x38, 0x6e, 0xc0, 0xfb],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9e, 0xd7, 0xfe, 0x6f, 0x93, 0xda, 0x38, 0x6e, 0xc0, 0xfb],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9e, 0xd7, 0xfe, 0x6f, 0x93, 0xda, 0x38, 0x6e, 0xc0, 0xfb],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9e, 0xd7, 0xfe, 0x6f, 0x93, 0xda, 0x38, 0x6e, 0xc0, 0xfb],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9e, 0xd7, 0xfe, 0x6f, 0x93, 0xda, 0x38, 0x6e, 0xc0, 0xfb],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9e, 0xd7, 0xfe, 0x6f, 0x93, 0xda, 0x38, 0x6e, 0xc0, 0xfb],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9e, 0xd7, 0xfe, 0x6f, 0x93, 0xda, 0x38, 0x6e, 0xc0, 0xfb],
        [0x00, 0xbf, 0x39, 0x19, 0xe1, 0x30, 0xf6, 0x03, 0x1d, 0x72, 0xf1, 0x04, 0x63, 0x14, 0xcb, 0x50],
    ]
    private static let padRows: [[UInt8]] = [
        [0x4d, 0x01, 0xfd, 0x1f, 0xbd, 0xb5, 0xd0, 0xc4, 0xf2, 0xff, 0x9c, 0x5f, 0x0d, 0x8f, 0x47, 0x61],
        [0x3e, 0x15, 0x55, 0x00, 0xc9, 0x2e, 0x05, 0x73, 0x67, 0x03, 0x74, 0x0a, 0x94, 0x5a, 0x91, 0x62],
        [0x91, 0xf9, 0xb5, 0x2f, 0x28, 0xa7, 0xc0, 0x2c, 0x3f, 0xd4, 0xc4, 0x56, 0xdb, 0xfe, 0x25, 0x44],
        [0x0f, 0x30, 0x9d, 0x17, 0x57, 0xe7, 0x2d, 0x4b, 0x18, 0x43, 0x99, 0x6d, 0xb3, 0xcd, 0xcc, 0x59],
        [0x94, 0xe2, 0x6c, 0xe1, 0xb3, 0x75, 0x31, 0xda, 0xdb, 0x46, 0xd8, 0xc7, 0x18, 0xfb, 0x64, 0xee],
        [0x45, 0xd0, 0x7f, 0x57, 0x86, 0xd5, 0x3e, 0xfd, 0x2d, 0xe3, 0x96, 0x4a, 0x45, 0x68, 0x82, 0xd4],
        [0xa4, 0xac, 0x08, 0x0e, 0x52, 0x09, 0x46, 0x83, 0x0f, 0x9a, 0xa0, 0xb9, 0x3a, 0x82, 0x52, 0x1d],
        [0x3b, 0xbd, 0xc1, 0x21, 0x19, 0xc4, 0xf7, 0xd2, 0x66, 0x2e, 0x27, 0x1b, 0x2c, 0xdc, 0x05, 0x76],
        [0x24, 0xcf, 0x99, 0x39, 0x4d, 0x7b, 0x1e, 0x9b, 0x5b, 0x25, 0x49, 0xf0, 0x07, 0x89, 0x3c, 0xf6],
        [0x5a, 0x1f, 0x9a, 0x95, 0x67, 0x14, 0xf4, 0x7e, 0x4c, 0x41, 0xcd, 0xfe, 0x3b, 0xb8, 0x81, 0x78],
        [0x61, 0x5d, 0x85, 0xdf, 0xa9, 0x9d, 0xbc, 0x20, 0xe1, 0xd2, 0x80, 0xcd, 0x8a, 0x53, 0x04, 0x87],
    ]
}
