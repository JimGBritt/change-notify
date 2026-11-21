import Foundation
import Testing
@testable import ChangeNotifyCore

@Suite struct DeviceFlowTests {
    @Test func parsesDeviceCode() throws {
        let json = #"""
        {"device_code":"dc","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device",
         "expires_in":899,"interval":5}
        """#
        let code = try GitHubDeviceFlow.parseCode(Data(json.utf8))
        #expect(code.userCode == "ABCD-1234")
        #expect(code.verificationURI.absoluteString == "https://github.com/login/device")
        #expect(code.interval == 5)
    }

    @Test func codeErrorSurfaces() {
        let json = #"{"error":"incorrect_client_credentials","error_description":"Bad client"}"#
        #expect(throws: DeviceFlowError.failed("Bad client")) {
            try GitHubDeviceFlow.parseCode(Data(json.utf8))
        }
    }

    @Test func pollStates() throws {
        func parse(_ s: String) throws -> GitHubDeviceFlow.PollResult {
            try GitHubDeviceFlow.parsePoll(Data(s.utf8))
        }
        #expect(try parse(#"{"access_token":"gho_x","token_type":"bearer"}"#) == .token("gho_x"))
        #expect(try parse(#"{"error":"authorization_pending"}"#) == .pending)
        #expect(try parse(#"{"error":"slow_down","interval":10}"#) == .slowDown(10))
        #expect(throws: DeviceFlowError.expired) { try parse(#"{"error":"expired_token"}"#) }
        #expect(throws: DeviceFlowError.denied) { try parse(#"{"error":"access_denied"}"#) }
    }
}
