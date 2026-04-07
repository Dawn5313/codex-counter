import Foundation
import XCTest

final class OpenAIAccountCSVServiceTests: CodexBarTestCase {
    func testMakeCSVExportsFixedHeaderAndActiveMarker() throws {
        let service = OpenAIAccountCSVService()
        let activeAccount = try self.makeOAuthAccount(accountID: "acct_active", email: "active@example.com", isActive: true)
        let inactiveAccount = try self.makeOAuthAccount(accountID: "acct_idle", email: "idle@example.com")

        let csv = service.makeCSV(from: [activeAccount, inactiveAccount])
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.first, OpenAIAccountCSVService.headerOrder.joined(separator: ","))
        XCTAssertEqual(lines.count, 3)

        let parsed = try service.parseCSV(csv)
        XCTAssertEqual(parsed.rowCount, 2)
        XCTAssertEqual(Set(parsed.accounts.map(\.accountId)), ["acct_active", "acct_idle"])
        XCTAssertEqual(parsed.activeAccountID, "acct_active")
    }

    func testParseCSVRejectsInvalidAccountIDMismatch() throws {
        let service = OpenAIAccountCSVService()
        let account = try self.makeOAuthAccount(accountID: "acct_valid", email: "user@example.com", isActive: true)
        let exported = service.makeCSV(from: [account])
        var lines = exported.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fields = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        fields[2] = "acct_other"
        lines[1] = fields.joined(separator: ",")
        let csv = lines.joined(separator: "\n")

        XCTAssertThrowsError(try service.parseCSV(csv)) { error in
            XCTAssertEqual(error as? OpenAIAccountCSVError, .accountIDMismatch(row: 2))
        }
    }

    func testParseCSVRejectsDuplicateAccountIDs() throws {
        let service = OpenAIAccountCSVService()
        let first = try self.makeOAuthAccount(accountID: "acct_same", email: "first@example.com", refreshToken: "refresh-1")
        let second = try self.makeOAuthAccount(accountID: "acct_same", email: "first@example.com", refreshToken: "refresh-2")

        let csv = service.makeCSV(from: [first, second])

        XCTAssertThrowsError(try service.parseCSV(csv)) { error in
            XCTAssertEqual(error as? OpenAIAccountCSVError, .duplicateAccountID)
        }
    }

    func testParseCSVRejectsMultipleActiveAccounts() throws {
        let service = OpenAIAccountCSVService()
        let first = try self.makeOAuthAccount(accountID: "acct_one", email: "one@example.com", isActive: true)
        let second = try self.makeOAuthAccount(accountID: "acct_two", email: "two@example.com", isActive: true)

        let csv = service.makeCSV(from: [first, second])

        XCTAssertThrowsError(try service.parseCSV(csv)) { error in
            XCTAssertEqual(error as? OpenAIAccountCSVError, .multipleActiveAccounts)
        }
    }

    func testParseCSVRejectsMissingRequiredColumns() {
        let service = OpenAIAccountCSVService()
        let csv = """
        format_version,email,account_id
        v1,user@example.com,acct_test
        """

        XCTAssertThrowsError(try service.parseCSV(csv)) { error in
            XCTAssertEqual(error as? OpenAIAccountCSVError, .missingRequiredColumns)
        }
    }

    func testParseCSVRejectsUnsupportedVersion() throws {
        let service = OpenAIAccountCSVService()
        let account = try self.makeOAuthAccount(accountID: "acct_version", email: "version@example.com", isActive: true)
        let exported = service.makeCSV(from: [account])
        var lines = exported.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fields = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        fields[0] = "v2"
        lines[1] = fields.joined(separator: ",")
        let csv = lines.joined(separator: "\n")

        XCTAssertThrowsError(try service.parseCSV(csv)) { error in
            XCTAssertEqual(error as? OpenAIAccountCSVError, .unsupportedFormatVersion)
        }
    }

    func testParseCSVRejectsInvalidActiveValue() throws {
        let service = OpenAIAccountCSVService()
        let account = try self.makeOAuthAccount(accountID: "acct_active_value", email: "active@example.com", isActive: true)
        let exported = service.makeCSV(from: [account])
        var lines = exported.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fields = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        fields[6] = "maybe"
        lines[1] = fields.joined(separator: ",")
        let csv = lines.joined(separator: "\n")

        XCTAssertThrowsError(try service.parseCSV(csv)) { error in
            XCTAssertEqual(error as? OpenAIAccountCSVError, .invalidActiveValue(row: 2))
        }
    }
}
