#!/bin/bash
# Test runner for hs2 command-line tool
# This script runs integration tests for hs2 similar to Hammerspoon's test suite

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT}"
HAMMERSPOON_APP="$BUILD_DIR/Debug/Hammerspoon 2.app"
HS2_BINARY="$BUILD_DIR/Debug/hs2"
TEST_FIXTURES="$PROJECT_ROOT/Hammerspoon 2Tests/Fixtures/hs2"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if [ ! -d "$HAMMERSPOON_APP" ]; then
        log_error "Hammerspoon 2.app not found at: $HAMMERSPOON_APP"
        log_error "Please build the project first"
        exit 1
    fi

    if [ ! -f "$HS2_BINARY" ]; then
        log_error "hs2 binary not found at: $HS2_BINARY"
        log_error "Please build the project first"
        exit 1
    fi

    if [ ! -d "$TEST_FIXTURES" ]; then
        log_error "Test fixtures not found at: $TEST_FIXTURES"
        exit 1
    fi

    log_info "All prerequisites met"
}

start_hammerspoon() {
    log_info "Starting Hammerspoon 2..."

    # Kill any existing instances (graceful first, then force)
    killall "Hammerspoon 2" 2>/dev/null || true
    sleep 1
    killall -9 "Hammerspoon 2" 2>/dev/null || true
    sleep 0.5

    # Start Hammerspoon 2
    open "$HAMMERSPOON_APP"
    sleep 3

    # Wait for it to be ready
    local retries=0
    local max_retries=10

    while [ $retries -lt $max_retries ]; do
        if "$HS2_BINARY" -q -c "print('ready')" >/dev/null 2>&1; then
            log_info "Hammerspoon 2 is ready"
            return 0
        fi
        retries=$((retries + 1))
        sleep 1
    done

    log_error "Hammerspoon 2 failed to start"
    return 1
}

stop_hammerspoon() {
    log_info "Stopping Hammerspoon 2..."
    killall "Hammerspoon 2" 2>/dev/null || true
    sleep 1
}

run_test() {
    local test_name="$1"
    local expected_exit_code="$2"
    shift 2

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Test $TESTS_RUN: $test_name ... "

    local output
    local exit_code

    set +e
    output=$("$@" 2>&1)
    exit_code=$?
    set -e

    if [ $exit_code -eq $expected_exit_code ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "    Expected exit code: $expected_exit_code, got: $exit_code"
        echo "    Output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

run_fixture_test() {
    local fixture_file="$1"
    local test_name="$(basename "$fixture_file" .js)"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Fixture: $test_name ... "

    local output
    local exit_code

    set +e
    output=$("$HS2_BINARY" -q "$fixture_file" 2>&1)
    exit_code=$?
    set -e

    # Special handling for error_test.js
    # JS errors return exit 65 (EX_DATAERR), errors reported via stderr
    if [[ "$test_name" == "error_test" ]]; then
        if [ $exit_code -eq 65 ]; then
            echo -e "${GREEN}PASS${NC} (JS error reported via stderr, exit 65)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            echo -e "${RED}FAIL${NC} (expected exit 65, got $exit_code)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    fi

    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "    Exit code: $exit_code"
        echo "    Output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

run_basic_tests() {
    echo ""
    log_info "Running basic functionality tests..."

    run_test "Simple print" 0 \
        "$HS2_BINARY" -q -c 'print("test")'

    run_test "Math operations" 0 \
        "$HS2_BINARY" -q -c 'print(2 + 2)'

    run_test "Multiple statements" 0 \
        "$HS2_BINARY" -q -c 'print(1); print(2); print(3)'

    run_test "Function definition" 0 \
        "$HS2_BINARY" -q -c 'function f() { return 42; } print(f());'

    run_test "hs namespace access" 0 \
        "$HS2_BINARY" -q -c 'print(typeof hs)'

    run_test "hs.timer access" 0 \
        "$HS2_BINARY" -q -c 'print(typeof hs.timer)'

    run_test "hs.timer helper" 0 \
        "$HS2_BINARY" -q -c 'print(hs.timer.minutes(5))'
}

run_error_tests() {
    echo ""
    log_info "Running error handling tests..."

    run_test "Syntax error detection" 65 \
        "$HS2_BINARY" -q -c 'invalid syntax;;'

    run_test "Runtime error detection" 65 \
        "$HS2_BINARY" -q -c 'throw new Error("test");'

    run_test "Undefined variable" 65 \
        "$HS2_BINARY" -q -c 'print(undefinedVar);'
}

run_fixture_tests() {
    echo ""
    log_info "Running fixture file tests..."

    if [ ! -d "$TEST_FIXTURES" ]; then
        log_warn "No test fixtures found, skipping"
        return
    fi

    for fixture in "$TEST_FIXTURES"/*.js; do
        if [ -f "$fixture" ]; then
            run_fixture_test "$fixture"
        fi
    done
}

run_stress_tests() {
    echo ""
    log_info "Running stress tests (sequential execution)..."

    echo -n "  Sequential execution (20 commands) ... "
    local failed=0
    for i in {1..20}; do
        if ! "$HS2_BINARY" -q -c "print('test $i')" >/dev/null 2>&1; then
            failed=1
            break
        fi
        # Small delay to allow port cleanup (realistic usage pattern)
        sleep 0.2
    done

    TESTS_RUN=$((TESTS_RUN + 1))
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    echo -n "  Multiple console.log in rapid succession (15 calls) ... "
    failed=0
    for i in {1..15}; do
        if ! "$HS2_BINARY" -q -c "console.log('console.log test $i')" >/dev/null 2>&1; then
            failed=1
            echo -e "\n    Failed on iteration $i"
            break
        fi
        # Small delay to allow port cleanup
        sleep 0.1
    done

    TESTS_RUN=$((TESTS_RUN + 1))
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

print_summary() {
    echo ""
    echo "=================================="
    echo "Test Results Summary"
    echo "=================================="
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo "=================================="

    if [ $TESTS_FAILED -eq 0 ]; then
        log_info "All tests passed!"
        return 0
    else
        log_error "$TESTS_FAILED test(s) failed"
        return 1
    fi
}

# Main execution
main() {
    echo "=================================="
    echo "hs2 Integration Test Suite"
    echo "=================================="

    check_prerequisites

    if ! start_hammerspoon; then
        log_error "Failed to start Hammerspoon 2"
        exit 1
    fi

    # Run test suites
    run_basic_tests
    run_error_tests
    run_fixture_tests
    run_stress_tests

    # Cleanup
    stop_hammerspoon

    # Print summary and exit
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
