//
//  NativeSAPSession.swift
//  ApplePackage
//
//  Created on 2026/10/15.
//

#if os(macOS)
    import Foundation
    import MachO

    /// FairPlay SAP backed by the copy of Apple's implementation already loaded
    /// with AppleMediaServices on this Mac.
    ///
    /// The entry points are private (non-exported) symbols, so `dlsym` cannot see
    /// them. The macOS shared cache keeps local symbols in each image's symbol
    /// table, so they are resolved by walking the in-memory `LC_SYMTAB` of the
    /// loaded framework. Names and calling conventions match ipatool's SAP
    /// runtime (internal/sap/machine), which emulates the same functions.
    final class NativeSAPSession: SAPPrimitives {
        private typealias InitializeFunction = @convention(c) (
            UnsafeMutablePointer<UInt64>, UnsafeRawPointer
        ) -> Int32
        private typealias ExchangeFunction = @convention(c) (
            UInt32, UnsafeRawPointer, UInt64, UnsafeRawPointer, UInt64,
            UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt32>
        ) -> Int32
        private typealias SignFunction = @convention(c) (
            UInt64, UnsafeRawPointer, UInt64, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
        ) -> Int32
        private typealias ReleaseFunction = @convention(c) (UInt64) -> Int32

        private struct Functions {
            let initialize: InitializeFunction
            let exchange: ExchangeFunction
            let sign: SignFunction
            let teardown: ReleaseFunction
            let dispose: ReleaseFunction
        }

        private static let frameworkPath = "/System/Library/PrivateFrameworks/AppleMediaServices.framework/AppleMediaServices"
        private static let maximumOutputSize: UInt64 = 1 << 20
        private static let resolved = Result { try resolveFunctions() }

        private let functions: Functions
        private let hardware: [UInt8]
        private let lock = NSLock()
        private var context: UInt64 = 0

        init(hardwareID: Data) throws {
            try ensure((1 ... 20).contains(hardwareID.count), Strings.sapInvalidHardwareID)
            functions = try Self.resolved.get()

            // Hardware block layout: little-endian UInt32 length, then the ID, padded to 24 bytes.
            var block = [UInt8](repeating: 0, count: 24)
            block[0] = UInt8(hardwareID.count)
            block.replaceSubrange(4 ..< 4 + hardwareID.count, with: hardwareID)
            hardware = block

            var value: UInt64 = 0
            let status = hardware.withUnsafeBytes { functions.initialize(&value, $0.baseAddress!) }
            try ensure(status == 0 && value != 0, "\(Strings.sapSetupFailed): initialize returned \(status)")
            context = value
        }

        deinit {
            if context != 0 { _ = functions.teardown(context) }
        }

        func exchange(version: UInt32, input: Data) throws -> (output: Data, state: UInt32) {
            lock.lock()
            defer { lock.unlock() }

            var pointer: UInt64 = 0
            var length: UInt64 = 0
            var state: UInt32 = 0
            let status = hardware.withUnsafeBytes { hardware in
                input.withUnsafeBytes { input in
                    functions.exchange(
                        version, hardware.baseAddress!, context,
                        input.baseAddress!, UInt64(input.count),
                        &pointer, &length, &state
                    )
                }
            }
            let output = try consume(pointer: pointer, length: length)
            try ensure(status == 0, "\(Strings.sapSetupFailed): exchange returned \(status)")
            return (output, state)
        }

        func sign(_ data: Data) throws -> Data {
            lock.lock()
            defer { lock.unlock() }

            var pointer: UInt64 = 0
            var length: UInt64 = 0
            let status = data.withUnsafeBytes { input in
                functions.sign(context, input.baseAddress!, UInt64(input.count), &pointer, &length)
            }
            let output = try consume(pointer: pointer, length: length)
            try ensure(status == 0 && !output.isEmpty, "\(Strings.sapSignFailed): status \(status)")
            return output
        }

        /// Copies an output buffer and hands it back to the SAP allocator.
        private func consume(pointer: UInt64, length: UInt64) throws -> Data {
            guard pointer != 0 else { return Data() }
            defer { _ = functions.dispose(pointer) }
            try ensure(length <= Self.maximumOutputSize, "\(Strings.sapSignFailed): output too large")
            guard let raw = UnsafeRawPointer(bitPattern: UInt(pointer)) else { return Data() }
            return Data(bytes: raw, count: Int(length))
        }

        // MARK: - Symbol resolution

        private static func resolveFunctions() throws -> Functions {
            guard dlopen(frameworkPath, RTLD_NOW) != nil else {
                try ensureFailed("\(Strings.sapUnavailable): unable to load AppleMediaServices")
            }
            let names = ["_cp2g1b9ro", "_Mib5yocT", "_Fc3vhtJDvr", "_IPaI1oem5iL", "_jEHf8Xzsv8K"]
            let symbols = localSymbols(imageName: "AppleMediaServices.framework", names: Set(names))
            let missing = names.filter { symbols[$0] == nil }
            try ensure(missing.isEmpty, "\(Strings.sapUnavailable): missing \(missing.joined(separator: ", "))")
            APLogger.debug("sap: resolved native entry points")

            return Functions(
                initialize: unsafeBitCast(symbols["_cp2g1b9ro"]!, to: InitializeFunction.self),
                exchange: unsafeBitCast(symbols["_Mib5yocT"]!, to: ExchangeFunction.self),
                sign: unsafeBitCast(symbols["_Fc3vhtJDvr"]!, to: SignFunction.self),
                teardown: unsafeBitCast(symbols["_IPaI1oem5iL"]!, to: ReleaseFunction.self),
                dispose: unsafeBitCast(symbols["_jEHf8Xzsv8K"]!, to: ReleaseFunction.self)
            )
        }

        /// dyld registers the versioned path (`.../Versions/A/AppleMediaServices`), so
        /// match the framework directory and binary name rather than the dlopen path.
        private static func localSymbols(imageName: String, names: Set<String>) -> [String: UnsafeRawPointer] {
            let binaryName = (imageName as NSString).deletingPathExtension
            for index in 0 ..< _dyld_image_count() {
                guard let name = _dyld_get_image_name(index).map({ String(cString: $0) }),
                      name.contains("/\(imageName)/"),
                      (name as NSString).lastPathComponent == binaryName,
                      let header = _dyld_get_image_header(index),
                      header.pointee.magic == MH_MAGIC_64
                else { continue }
                return localSymbols(
                    header: UnsafeRawPointer(header),
                    commandCount: header.pointee.ncmds,
                    slide: _dyld_get_image_vmaddr_slide(index),
                    names: names
                )
            }
            return [:]
        }

        private static func localSymbols(
            header: UnsafeRawPointer,
            commandCount: UInt32,
            slide: Int,
            names: Set<String>
        ) -> [String: UnsafeRawPointer] {
            var linkedit: segment_command_64?
            var text: segment_command_64?
            var symtab: symtab_command?

            var command = header.advanced(by: MemoryLayout<mach_header_64>.size)
            for _ in 0 ..< commandCount {
                let load = command.load(as: load_command.self)
                switch load.cmd {
                case UInt32(LC_SEGMENT_64):
                    let segment = command.load(as: segment_command_64.self)
                    switch segmentName(segment) {
                    case SEG_LINKEDIT: linkedit = segment
                    case SEG_TEXT: text = segment
                    default: break
                    }
                case UInt32(LC_SYMTAB):
                    symtab = command.load(as: symtab_command.self)
                default:
                    break
                }
                command = command.advanced(by: Int(load.cmdsize))
            }
            guard let linkedit, let text, let symtab,
                  let base = UnsafeRawPointer(bitPattern: Int(linkedit.vmaddr) + slide - Int(linkedit.fileoff))
            else { return [:] }

            let textRange = text.vmaddr ..< text.vmaddr + text.vmsize
            let entries = base.advanced(by: Int(symtab.symoff)).assumingMemoryBound(to: nlist_64.self)
            let strings = base.advanced(by: Int(symtab.stroff)).assumingMemoryBound(to: CChar.self)

            var result: [String: UnsafeRawPointer] = [:]
            for index in 0 ..< Int(symtab.nsyms) {
                let entry = entries[index]
                guard entry.n_type & UInt8(N_STAB) == 0,
                      entry.n_type & UInt8(N_TYPE) == UInt8(N_SECT),
                      textRange.contains(entry.n_value),
                      entry.n_un.n_strx < symtab.strsize
                else { continue }
                let name = String(cString: strings.advanced(by: Int(entry.n_un.n_strx)))
                guard names.contains(name), let address = UnsafeRawPointer(bitPattern: Int(entry.n_value) + slide) else { continue }
                result[name] = address
                if result.count == names.count { break }
            }
            return result
        }

        private static func segmentName(_ segment: segment_command_64) -> String {
            withUnsafeBytes(of: segment.segname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        }
    }
#endif
