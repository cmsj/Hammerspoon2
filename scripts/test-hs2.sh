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
PROJECT_FILE="$PROJECT_ROOT/Hammerspoon 2.xcodeproj"
TEST_FIXTURES="$PROJECT_ROOT/Hammerspoon 2Tests/Fixtures/hs2"

# Build first, then use the known output path
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

build_project() {
    log_info "Building Hammerspoon 2 and hs2..."

    local build_output
    build_output=$(xcodebuild build -scheme Development -project "$PROJECT_FILE" \
        -configuration Debug -destination "platform=macOS,arch=arm64" \
        -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')

    if [ -z "$build_output" ]; then
        log_error "Could not determine build output directory"
        exit 1
    fi

    BUILD_DIR="$build_output"

    # Now do the actual build
    if ! xcodebuild build -scheme Development -project "$PROJECT_FILE" \
        -configuration Debug -destination "platform=macOS,arch=arm64" \
        CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5 | grep -q "BUILD SUCCEEDED"; then
        log_error "Build failed"
        exit 1
    fi

    HAMMERSPOON_APP="$BUILD_DIR/Hammerspoon 2.app"
    HS2_BINARY="$BUILD_DIR/hs2"

    log_info "Build succeeded"
    log_info "  App: $HAMMERSPOON_APP"
    log_info "  hs2: $HS2_BINARY"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if [ ! -d "$PROJECT_ROOT" ]; then
        log_error "Project root not found at: $PROJECT_ROOT"
        exit 1
    fi

    if [ ! -d "$PROJECT_FILE" ]; then
        log_error "Xcode project not found at: $PROJECT_FILE"
        exit 1
    fi

    log_info "All prerequisites met"
}

start_hammerspoon() {
    log_info "Starting Hammerspoon 2..."

    # Kill any existing instances
    killall "Hammerspoon 2" 2>/dev/null || true
    sleep 2

    # Start Hammerspoon 2
    open "$HAMMERSPOON_APP"
    sleep 5

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
    local expected_output="$3"
    shift 3

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Test $TESTS_RUN: $test_name ... "

    local stdout_output
    local stderr_output
    local exit_code

    set +e
    stdout_output=$("$@" 2>/tmp/hs2_test_stderr)
    exit_code=$?
    stderr_output=$(cat /tmp/hs2_test_stderr)
    set -e

    local failed=0
    local failure_reasons=""

    if [ $exit_code -ne $expected_exit_code ]; then
        failed=1
        failure_reasons="    Expected exit code: $expected_exit_code, got: $exit_code\n"
    fi

    if [ -n "$expected_output" ]; then
        # Check stdout for success tests, stderr for error tests
        if [ $expected_exit_code -eq 0 ]; then
            if [ "$stdout_output" != "$expected_output" ]; then
                failed=1
                failure_reasons="${failure_reasons}    Expected output: $expected_output\n    Actual output:   $stdout_output\n"
            fi
        else
            if ! echo "$stderr_output" | grep -q "$expected_output"; then
                failed=1
                failure_reasons="${failure_reasons}    Expected stderr to contain: $expected_output\n    Actual stderr: $stderr_output\n"
            fi
        fi
    fi

    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo -e "$failure_reasons"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

run_fixture_test() {
    local fixture_file="$1"
    local test_name="$(basename "$fixture_file" .js)"
    local expected_file="${fixture_file%.js}.expected"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Fixture: $test_name ... "

    local stdout_output
    local stderr_output
    local exit_code

    set +e
    stdout_output=$("$HS2_BINARY" "$fixture_file" 2>/tmp/hs2_test_stderr)
    exit_code=$?
    stderr_output=$(cat /tmp/hs2_test_stderr)
    set -e

    local failed=0
    local failure_reasons=""

    # Special handling for error_test.js
    # JS errors return exit 65 (EX_DATAERR), errors reported via stderr
    if [[ "$test_name" == "error_test" ]]; then
        if [ $exit_code -ne 65 ]; then
            failed=1
            failure_reasons="    Expected exit 65, got $exit_code\n"
        fi
        if ! echo "$stderr_output" | grep -q "Error"; then
            failed=1
            failure_reasons="${failure_reasons}    Expected stderr to contain 'Error'\n    Actual stderr: $stderr_output\n"
        fi
        if [ $failed -eq 0 ]; then
            echo -e "${GREEN}PASS${NC} (JS error reported via stderr, exit 65)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}FAIL${NC}"
            echo -e "$failure_reasons"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        return $failed
    fi

    # Check exit code
    if [ $exit_code -ne 0 ]; then
        failed=1
        failure_reasons="    Exit code: $exit_code\n    Output: $stdout_output\n"
    fi

    # Check output against .expected file if it exists
    if [ -f "$expected_file" ]; then
        local expected_output
        expected_output=$(cat "$expected_file")
        if [ "$stdout_output" != "$expected_output" ]; then
            failed=1
            failure_reasons="${failure_reasons}    Output mismatch:\n    Expected: $(head -3 "$expected_file")\n    Actual:   $(echo "$stdout_output" | head -3)\n"
        fi
    fi

    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        echo -e "$failure_reasons"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    return $failed
}

run_basic_tests() {
    echo ""
    log_info "Running basic functionality tests..."

    run_test "Simple print" 0 "test" \
        "$HS2_BINARY" -c 'print("test")'

    run_test "Math operations" 0 "4" \
        "$HS2_BINARY" -c 'print(2 + 2)'

    run_test "Multiple statements" 0 "$(printf '1\n2\n3')" \
        "$HS2_BINARY" -c 'print(1); print(2); print(3)'

    run_test "Function definition" 0 "42" \
        "$HS2_BINARY" -c 'function f() { return 42; } print(f());'

    run_test "hs namespace access" 0 "object" \
        "$HS2_BINARY" -c 'print(typeof hs)'

    run_test "hs.timer access" 0 "object" \
        "$HS2_BINARY" -c 'print(typeof hs.timer)'

    run_test "hs.timer helper" 0 "300" \
        "$HS2_BINARY" -c 'print(hs.timer.minutes(5))'
}

run_error_tests() {
    echo ""
    log_info "Running error handling tests..."

    run_test "Syntax error detection" 65 "SyntaxError" \
        "$HS2_BINARY" -c 'invalid syntax;;'

    run_test "Runtime error detection" 65 "Error: test" \
        "$HS2_BINARY" -c 'throw new Error("test");'

    run_test "Undefined variable" 65 "ReferenceError" \
        "$HS2_BINARY" -c 'print(undefinedVar);'
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

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Main execution
main() {
    echo "=================================="
    echo "hs2 Integration Test Suite"
    echo "=================================="

    check_prerequisites
    build_project

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
