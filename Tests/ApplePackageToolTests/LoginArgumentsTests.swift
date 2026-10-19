@testable import ApplePackageTool
import ArgumentParser
import Testing

struct LoginArgumentsTests {
    @Test(arguments: ["--sap-context", "--sap-iv-address"])
    func obsoleteSAPOptionsAreRejected(_ option: String) {
        #expect(throws: (any Error).self) { try ApplePackageTool.parseAsRoot(["login", "reader@example.invalid", option, "unused"]) }
    }

    @Test
    func passwordCanBeProvidedOutsideArguments() throws {
        let command = try #require(ApplePackageTool.parseAsRoot(["login", "reader@example.invalid"]) as? Login)
        #expect(command.password == nil)
        #expect(command.email == "reader@example.invalid")
    }

    @Test
    func positionalPasswordRemainsSupported() throws {
        let command = try #require(ApplePackageTool.parseAsRoot(["login", "reader@example.invalid", "test-password"]) as? Login)
        #expect(command.password == "test-password")
    }

    @Test
    func verificationCodeAndGUIDAreNormalized() throws {
        let command = try #require(
            ApplePackageTool.parseAsRoot(["login", "reader@example.invalid", "--code", " 012345 ", "--guid", "aabbcc001122"]) as? Login)
        #expect(command.code == "012345")
        #expect(command.globalOptions.guid == "AABBCC001122")
    }

    @Test(arguments: ["", "12345", "1234567", "12345x", "１２３４５６"])
    func invalidVerificationCodeIsRejected(_ code: String) {
        #expect(throws: (any Error).self) { try ApplePackageTool.parseAsRoot(["login", "reader@example.invalid", "--code", code]) }
    }

    @Test(arguments: ["", "AABBCC", "AA:BB:CC:DD:EE:FF", "AABBCCDDEEGG"])
    func invalidGUIDIsRejected(_ guid: String) {
        #expect(throws: (any Error).self) { try ApplePackageTool.parseAsRoot(["login", "reader@example.invalid", "--guid", guid]) }
    }

    @Test(arguments: [["login", "   "], ["login", "reader@example.invalid", ""]])
    func emptyCredentialsAreRejected(_ arguments: [String]) {
        #expect(throws: (any Error).self) { try ApplePackageTool.parseAsRoot(arguments) }
    }
}
