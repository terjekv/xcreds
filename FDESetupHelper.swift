//
//  FDESetupHelper.swift
//  XCreds
//
//  Uses the documented fdesetup input property-list interface to authorize
//  the next FileVault restart without placing credentials in process arguments.
//

import Foundation

/// Authorizes a single FileVault restart using an existing FileVault user.
///
/// The restart is delayed indefinitely (`-delayminutes -1`), so this function
/// prepares the next restart but does not restart the Mac itself.
func filevaultAuth(username: String, password: String) -> Bool {
    guard !username.isEmpty, !password.isEmpty else {
        return false
    }

    let credentials = [
        "Username": username,
        "Password": password,
    ]

    guard let input = try? PropertyListSerialization.data(
        fromPropertyList: credentials,
        format: .xml,
        options: 0
    ) else {
        return false
    }

    let process = Process()
    let inputPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
    process.arguments = ["authrestart", "-inputplist", "-delayminutes", "-1"]
    process.standardInput = inputPipe
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        inputPipe.fileHandleForWriting.write(input)
        try inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationReason == .exit && process.terminationStatus == 0
    } catch {
        try? inputPipe.fileHandleForWriting.close()
        return false
    }
}
