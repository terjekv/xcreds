//
//  SecureToken.swift
//  XCreds
//
//  Local secure-token and bootstrap-token status helper.
//

import Foundation

struct BootstrapTokenStatus {
    let isSupported: Bool
    let isEscrowed: Bool
}

enum SecureTokenError: Error {
    case bootstrapTokenStatusUnavailable(String)
}

final class SecureToken: DSQueryable {
    /// Returns local, non-system users that currently have a Secure Token.
    ///
    /// `sysadminctl` writes this status to standard error, which `cliTask`
    /// intentionally combines with standard output.
    func secureTokenUsers() throws -> [String: String] {
        let users = try getAllNonSystemUsers()
        var tokenUsers = [String: String]()

        for user in users {
            guard let username = user.recordName else {
                continue
            }
            let output = cliTask(
                "/usr/sbin/sysadminctl",
                arguments: ["-secureTokenStatus", username]
            )

            if output.range(
                of: "Secure token is ENABLED",
                options: String.CompareOptions.caseInsensitive
            ) != nil {
                tokenUsers[username] = username
            }
        }

        return tokenUsers
    }

    /// Returns the number of ordinary local users that do not have a token.
    func numberOfUsersWithoutSecureTokens() -> Int? {
        guard let users = try? getAllNonSystemUsers(),
              let tokenUsers = try? secureTokenUsers() else {
            return nil
        }

        return max(0, users.count - tokenUsers.count)
    }

    /// Reads the MDM bootstrap-token state reported by Apple's `profiles` tool.
    func bootstrapTokenStatus() throws -> BootstrapTokenStatus {
        let output = cliTask(
            "/usr/bin/profiles",
            arguments: ["status", "-type", "bootstraptoken"]
        )

        guard let isEscrowed = boolValue(
            in: output,
            lineContaining: "escrowed"
        ) else {
            throw SecureTokenError.bootstrapTokenStatusUnavailable(output)
        }

        let isSupported = boolValue(
            in: output,
            lineContaining: "supported"
        ) ?? false

        return BootstrapTokenStatus(
            isSupported: isSupported,
            isEscrowed: isEscrowed
        )
    }

    private func boolValue(
        in output: String,
        lineContaining marker: String
    ) -> Bool? {
        let matchingLine = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { line in
                line.range(of: marker, options: [.caseInsensitive]) != nil
            }

        guard let value = matchingLine?
            .split(separator: ":")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return nil
        }

        switch value {
        case "yes", "true", "enabled":
            return true
        case "no", "false", "disabled":
            return false
        default:
            return nil
        }
    }
}
