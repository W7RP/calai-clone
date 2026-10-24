import Testing
@testable import CalorieTracker

// Keeps the test target compiling until real logic (PKCE, parsing, nutrition math) lands.
@Test func appModuleLoads() {
    #expect(Bool(true))
}
