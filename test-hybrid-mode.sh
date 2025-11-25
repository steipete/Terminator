#!/bin/bash

# Comprehensive test script for Terminator hybrid mode
# This script tests various aspects of the hybrid mode implementation

set -e

echo "======================================"
echo "Terminator Hybrid Mode Test Suite"
echo "======================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_pattern="$3"
    local should_contain="${4:-true}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test $TESTS_RUN: $test_name... "
    
    # Run command and capture output
    output=$(eval "$command" 2>&1) || true
    
    if [ "$should_contain" = "true" ]; then
        if echo "$output" | grep -q "$expected_pattern"; then
            echo -e "${GREEN}PASSED${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            echo -e "${RED}FAILED${NC}"
            echo "  Expected to contain: $expected_pattern"
            echo "  Actual output (first 5 lines):"
            echo "$output" | head -5 | sed 's/^/    /'
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        if echo "$output" | grep -q "$expected_pattern"; then
            echo -e "${RED}FAILED${NC}"
            echo "  Expected NOT to contain: $expected_pattern"
            echo "  But it was found in output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        else
            echo -e "${GREEN}PASSED${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        fi
    fi
}

# Test 1: Verify hybrid mode is activated with TERMINATOR_EXPERIMENTAL_AX=true
echo -e "\n${YELLOW}Testing hybrid mode activation...${NC}"
run_test "Hybrid mode activation" \
    "TERMINATOR_EXPERIMENTAL_AX=true TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator info 2>&1" \
    "Instantiating HybridAppleTerminalControl"

run_test "Hybrid controller initialization" \
    "TERMINATOR_EXPERIMENTAL_AX=true TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator info 2>&1" \
    "TerminalAppController initialized for Terminal using Hybrid"

run_test "AX features enabled" \
    "TERMINATOR_EXPERIMENTAL_AX=true TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator info 2>&1" \
    "Initialized hybrid controller for Terminal with AX features: windows=true, focus=true, busy=true"

# Test 2: Verify traditional mode when environment variable is not set
echo -e "\n${YELLOW}Testing traditional mode...${NC}"
run_test "Traditional mode activation" \
    "TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator info 2>&1" \
    "Instantiating AppleTerminalControl"

run_test "Traditional controller initialization" \
    "TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator info 2>&1" \
    "TerminalAppController initialized for Terminal using Traditional"

run_test "No hybrid mode in traditional" \
    "TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator info 2>&1" \
    "HybridAppleTerminalControl" \
    "false"

# Test 3: Test individual AX feature flags
echo -e "\n${YELLOW}Testing individual AX feature flags...${NC}"
run_test "AX windows flag only" \
    "TERMINATOR_AX_WINDOWS=true TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator info 2>&1" \
    "Instantiating HybridAppleTerminalControl"

run_test "AX focus flag only" \
    "TERMINATOR_AX_FOCUS=true TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator info 2>&1" \
    "Instantiating HybridAppleTerminalControl"

run_test "Partial AX features" \
    "TERMINATOR_AX_WINDOWS=true TERMINATOR_AX_FOCUS=true TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator info 2>&1" \
    "AX features: windows=true, focus=true, busy=false"

# Test 4: Test fallback behavior
echo -e "\n${YELLOW}Testing fallback behavior...${NC}"
run_test "AX permission warning" \
    "TERMINATOR_EXPERIMENTAL_AX=true TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator info 2>&1" \
    "Accessibility permission not granted\\|Enhanced AX enumeration failed"

run_test "Falls back to AppleScript" \
    "TERMINATOR_EXPERIMENTAL_AX=true TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator sessions --json 2>&1" \
    "falling back to AppleScript\\|AppleScript execution"

# Test 5: Verify all commands use TerminalAppController
echo -e "\n${YELLOW}Testing command integration...${NC}"
run_test "Sessions command uses TerminalAppController" \
    "TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator sessions --json 2>&1" \
    "\\[Controller Facade\\] Listing sessions"

run_test "Execute command uses TerminalAppController" \
    "TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator execute test-tag --command 'echo test' 2>&1" \
    "\\[Controller Facade\\] Executing command"

run_test "Focus command uses TerminalAppController" \
    "TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator focus --tag test-tag 2>&1" \
    "\\[Controller Facade\\] Focusing session"

run_test "Read command uses TerminalAppController" \
    "TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator read --tag test-tag 2>&1" \
    "\\[Controller Facade\\] Reading session"

run_test "Kill command uses TerminalAppController" \
    "TERMINATOR_LOG_LEVEL=debug timeout 2 bin/terminator kill --tag test-tag --focus-on-kill false 2>&1" \
    "\\[Controller Facade\\] Killing process"

# Test 6: Test iTerm hybrid mode
echo -e "\n${YELLOW}Testing iTerm hybrid mode...${NC}"
run_test "iTerm hybrid mode activation" \
    "TERMINATOR_EXPERIMENTAL_AX=true TERMINATOR_LOG_LEVEL=debug TERMINATOR_APP=iTerm timeout 2 bin/terminator info 2>&1" \
    "Instantiating HybridITermControl"

# Test 7: Test that hybrid mode respects terminal app setting
echo -e "\n${YELLOW}Testing terminal app configuration...${NC}"
run_test "Respects TERMINATOR_APP setting" \
    "TERMINATOR_EXPERIMENTAL_AX=true TERMINATOR_LOG_LEVEL=debug TERMINATOR_APP=iTerm timeout 2 bin/terminator info 2>&1" \
    "TerminalAppController initialized for iTerm using Hybrid"

# Summary
echo -e "\n======================================"
echo "Test Summary"
echo "======================================"
echo "Total tests run: $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✅${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed! ❌${NC}"
    exit 1
fi