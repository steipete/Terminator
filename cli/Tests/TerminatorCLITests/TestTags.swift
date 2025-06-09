import Testing

// MARK: - Central Test Tags Definition

extension Tag {
    // Command-specific tags
    @Tag static var exec: Self
    @Tag static var info: Self
    @Tag static var list: Self
    @Tag static var read: Self
    @Tag static var kill: Self
    @Tag static var focus: Self

    // Feature-specific tags
    @Tag static var parameters: Self
    @Tag static var environment: Self
    @Tag static var configuration: Self
    @Tag static var json: Self
    @Tag static var filtering: Self
    @Tag static var grouping: Self
    @Tag static var backgroundExecution: Self
    @Tag static var projectPath: Self

    // Terminal-specific tags
    @Tag static var appleTerminal: Self
    @Tag static var iTerm: Self
    @Tag static var ghosty: Self

    // Test characteristic tags
    @Tag static var fast: Self
    @Tag static var integration: Self
    @Tag static var flaky: Self
}
