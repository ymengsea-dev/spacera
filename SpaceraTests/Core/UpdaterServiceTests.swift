import Testing
@testable import Spacera

struct UpdaterServiceTests {
    @Test func disabledWhenFeedOrKeyMissing() {
        #expect(!UpdaterService.hasValidConfiguration(info: [:]))
        #expect(!UpdaterService.hasValidConfiguration(info: ["SUFeedURL": "", "SUPublicEDKey": ""]))
        #expect(!UpdaterService.hasValidConfiguration(info: ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": ""]))
    }

    @Test func rejectsNonHTTPSFeed() {
        #expect(!UpdaterService.hasValidConfiguration(info: ["SUFeedURL": "http://example.com/appcast.xml", "SUPublicEDKey": "abc"]))
    }

    @Test func enabledWithHTTPSFeedAndKey() {
        #expect(UpdaterService.hasValidConfiguration(info: ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "abc"]))
    }
}
