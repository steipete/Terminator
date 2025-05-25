@testable import TerminatorCLI
import XCTest

// Main test suite that ensures all command tests are included
final class TerminatorCLITests: XCTestCase {
    static var allTests = [
        ("BaseTerminatorTests", BaseTerminatorTests.allTests),
        ("InfoCommandTests", InfoCommandTests.allTests),
        ("ListCommandTests", ListCommandTests.allTests),
        ("FocusCommandTests", FocusCommandTests.allTests),
        ("ReadCommandTests", ReadCommandTests.allTests),
        ("KillCommandTests", KillCommandTests.allTests),
        ("ExecCommandTests", ExecCommandTests.allTests),
        ("ExecCommandGroupingTests", ExecCommandGroupingTests.allTests),
        ("ExecCommandITermTests", ExecCommandITermTests.allTests),
    ]
}
