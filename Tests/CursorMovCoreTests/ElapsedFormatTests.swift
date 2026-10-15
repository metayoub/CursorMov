import Foundation
import Testing
@testable import CursorMovCore

@Test func formatsElapsed() {
    #expect(formatElapsed(0) == "0m")
    #expect(formatElapsed(59) == "0m")
    #expect(formatElapsed(45 * 60) == "45m")
    #expect(formatElapsed(72 * 60) == "1h 12m")
    #expect(formatElapsed(3 * 3600) == "3h 0m")
    #expect(formatElapsed(-5) == "0m")
}
