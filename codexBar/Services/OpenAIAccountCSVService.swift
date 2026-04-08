import Foundation

struct ParsedOpenAIAccountCSV {
    let accounts: [TokenAccount]
    let activeAccountID: String?
    let rowCount: Int
}

enum OpenAIAccountCSVError: LocalizedError, Equatable {
    case emptyFile
    case missingRequiredColumns
    case unsupportedFormatVersion
    case invalidCSV(row: Int)
    case missingRequiredValue(row: Int)
    case invalidAccount(row: Int)
    case accountIDMismatch(row: Int)
    case emailMismatch(row: Int)
    case duplicateAccountID
    case multipleActiveAccounts
    case invalidActiveValue(row: Int)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return L.openAICSVEmptyFile
        case .missingRequiredColumns:
            return L.openAICSVMissingColumns
        case .unsupportedFormatVersion:
            return L.openAICSVUnsupportedVersion
        case let .invalidCSV(row):
            return L.openAICSVInvalidRow(row)
        case let .missingRequiredValue(row):
            return L.openAICSVMissingRequiredValue(row)
        case let .invalidAccount(row):
            return L.openAICSVInvalidAccount(row)
        case let .accountIDMismatch(row):
            return L.openAICSVAccountIDMismatch(row)
        case let .emailMismatch(row):
            return L.openAICSVEmailMismatch(row)
        case .duplicateAccountID:
            return L.openAICSVDuplicateAccounts
        case .multipleActiveAccounts:
            return L.openAICSVMultipleActiveAccounts
        case let .invalidActiveValue(row):
            return L.openAICSVInvalidActiveValue(row)
        }
    }
}

struct OpenAIAccountCSVService {
    static let formatVersion = "v1"
    static let headerOrder = [
        "format_version",
        "email",
        "account_id",
        "access_token",
        "refresh_token",
        "id_token",
        "is_active",
    ]

    func makeCSV(from accounts: [TokenAccount]) -> String {
        var rows = [Self.headerOrder.joined(separator: ",")]
        rows.append(
            contentsOf: accounts.map { account in
                [
                    Self.formatVersion,
                    account.email,
                    account.accountId,
                    account.accessToken,
                    account.refreshToken,
                    account.idToken,
                    account.isActive ? "true" : "false",
                ]
                .map(self.escapeCSVField)
                .joined(separator: ",")
            }
        )
        return rows.joined(separator: "\n") + "\n"
    }

    func parseCSV(_ text: String) throws -> ParsedOpenAIAccountCSV {
        let normalized = self.normalize(text)
        let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let headerIndex = rawLines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) else {
            throw OpenAIAccountCSVError.emptyFile
        }

        let headerRowNumber = headerIndex + 1
        let headers = try self.parseCSVLine(rawLines[headerIndex], rowNumber: headerRowNumber).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let headerSet = Set(headers)
        guard headerSet.count == headers.count,
              headerSet.isSuperset(of: Set(Self.headerOrder)) else {
            throw OpenAIAccountCSVError.missingRequiredColumns
        }

        let headerIndexMap = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })
        var accounts: [TokenAccount] = []
        var seenAccountIDs: Set<String> = []
        var activeAccountID: String?

        for lineIndex in rawLines.index(after: headerIndex)..<rawLines.endIndex {
            let line = rawLines[lineIndex]
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            let rowNumber = lineIndex + 1
            let columns = try self.parseCSVLine(line, rowNumber: rowNumber)
            guard columns.count == headers.count else {
                throw OpenAIAccountCSVError.invalidCSV(row: rowNumber)
            }

            func value(for key: String) -> String {
                guard let index = headerIndexMap[key] else {
                    preconditionFailure("Validated CSV header missing column: \(key)")
                }
                let field = columns[index]
                return field.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard value(for: "format_version").lowercased() == Self.formatVersion else {
                throw OpenAIAccountCSVError.unsupportedFormatVersion
            }

            let accessToken = value(for: "access_token")
            let refreshToken = value(for: "refresh_token")
            let idToken = value(for: "id_token")
            guard accessToken.isEmpty == false,
                  refreshToken.isEmpty == false,
                  idToken.isEmpty == false else {
                throw OpenAIAccountCSVError.missingRequiredValue(row: rowNumber)
            }

            let builtAccount = AccountBuilder.build(
                from: OAuthTokens(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    idToken: idToken
                )
            )
            guard builtAccount.accountId.isEmpty == false else {
                throw OpenAIAccountCSVError.invalidAccount(row: rowNumber)
            }

            let declaredAccountID = value(for: "account_id")
            if declaredAccountID.isEmpty == false &&
                declaredAccountID != builtAccount.accountId &&
                declaredAccountID != builtAccount.remoteAccountId {
                throw OpenAIAccountCSVError.accountIDMismatch(row: rowNumber)
            }

            let declaredEmail = value(for: "email")
            if declaredEmail.isEmpty == false && declaredEmail != builtAccount.email {
                throw OpenAIAccountCSVError.emailMismatch(row: rowNumber)
            }

            if seenAccountIDs.insert(builtAccount.accountId).inserted == false {
                throw OpenAIAccountCSVError.duplicateAccountID
            }

            let isActive = try self.parseActiveFlag(value(for: "is_active"), rowNumber: rowNumber)
            if isActive {
                if activeAccountID != nil {
                    throw OpenAIAccountCSVError.multipleActiveAccounts
                }
                activeAccountID = builtAccount.accountId
            }

            var account = builtAccount
            account.isActive = false
            accounts.append(account)
        }

        guard accounts.isEmpty == false else {
            throw OpenAIAccountCSVError.emptyFile
        }

        return ParsedOpenAIAccountCSV(
            accounts: accounts,
            activeAccountID: activeAccountID,
            rowCount: accounts.count
        )
    }

    private func normalize(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if normalized.first == "\u{FEFF}" {
            normalized.removeFirst()
        }
        return normalized
    }

    private func parseActiveFlag(_ value: String, rowNumber: Int) throws -> Bool {
        switch value.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            throw OpenAIAccountCSVError.invalidActiveValue(row: rowNumber)
        }
    }

    private func parseCSVLine(_ line: String, rowNumber: Int) throws -> [String] {
        let characters = Array(line)
        var fields: [String] = []
        var current = ""
        var index = 0
        var isQuoted = false

        while index < characters.count {
            let character = characters[index]
            if isQuoted {
                if character == "\"" {
                    let nextIndex = index + 1
                    if nextIndex < characters.count && characters[nextIndex] == "\"" {
                        current.append("\"")
                        index += 1
                    } else {
                        isQuoted = false
                    }
                } else {
                    current.append(character)
                }
            } else {
                switch character {
                case ",":
                    fields.append(current)
                    current = ""
                case "\"":
                    guard current.isEmpty else {
                        throw OpenAIAccountCSVError.invalidCSV(row: rowNumber)
                    }
                    isQuoted = true
                default:
                    current.append(character)
                }
            }
            index += 1
        }

        guard isQuoted == false else {
            throw OpenAIAccountCSVError.invalidCSV(row: rowNumber)
        }
        fields.append(current)
        return fields
    }

    private func escapeCSVField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
