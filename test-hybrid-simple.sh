#!/bin/bash

echo "Testing Hybrid Mode Implementation"
echo "=================================="
echo ""

# Test 1: Hybrid mode activation
echo "Test 1: Hybrid mode activation (TERMINATOR_EXPERIMENTAL_AX=true)"
echo "Running: TERMINATOR_EXPERIMENTAL_AX=true bin/terminator info"
echo "Expected: Should see 'Instantiating HybridAppleTerminalControl' in logs"
echo ""
TERMINATOR_EXPERIMENTAL_AX=true TERMINATOR_LOG_LEVEL=debug bin/terminator info 2>&1 | grep -A5 -B5 "Hybrid" | head -20
echo ""
echo "---"

# Test 2: Traditional mode
echo -e "\nTest 2: Traditional mode (no environment variable)"
echo "Running: bin/terminator info"
echo "Expected: Should see 'Instantiating AppleTerminalControl' in logs"
echo ""
TERMINATOR_LOG_LEVEL=debug bin/terminator info 2>&1 | grep -A5 -B5 "AppleTerminalControl" | head -20
echo ""
echo "---"

# Test 3: Individual feature flags
echo -e "\nTest 3: Individual AX feature flags"
echo "Running: TERMINATOR_AX_WINDOWS=true TERMINATOR_AX_FOCUS=true bin/terminator info"
echo "Expected: Should activate hybrid mode with partial features"
echo ""
TERMINATOR_AX_WINDOWS=true TERMINATOR_AX_FOCUS=true TERMINATOR_LOG_LEVEL=debug bin/terminator info 2>&1 | grep -E "(Hybrid|AX features)" | head -10
echo ""
echo "---"

# Test 4: Check all commands use TerminalAppController
echo -e "\nTest 4: Verify commands use TerminalAppController"
echo "Running: bin/terminator sessions --json"
echo "Expected: Should see '[Controller Facade]' in logs"
echo ""
TERMINATOR_LOG_LEVEL=debug bin/terminator sessions --json 2>&1 | grep "Controller Facade" | head -5
echo ""

echo "Test complete!"