import SwitchCore
import Testing

@Suite struct WindowTitleTests {
    @Test func dropsTheAppNameAtTheEnd() {
        #expect(windowTitle("main.swift — AppSwipe — Visual Studio Code", appName: "Visual Studio Code")
            == "main.swift — AppSwipe")
    }

    @Test func dropsTheAppNameBeforeAProfile() {
        #expect(windowTitle("Подписки - YouTube - Google Chrome – Никита (Nikita)", appName: "Google Chrome")
            == "Подписки - YouTube – Никита (Nikita)")
    }

    @Test func keepsTheAppNameInsideAPart() {
        #expect(windowTitle("Google Chrome tips - Notes", appName: "Google Chrome") == "Google Chrome tips - Notes")
        #expect(windowTitle("Review - Safari Extensions", appName: "Safari") == "Review - Safari Extensions")
    }

    @Test func keepsATitleThatIsOnlyTheAppName() {
        #expect(windowTitle("T3 Code (Nightly)", appName: "T3 Code (Nightly)") == "T3 Code (Nightly)")
    }

    @Test func keepsATitleWithoutTheAppName() {
        #expect(windowTitle("Downloads", appName: "Finder") == "Downloads")
    }
}
