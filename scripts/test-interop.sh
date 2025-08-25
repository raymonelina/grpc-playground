#!/bin/bash

# Interoperability test runner for gRPC bidirectional streaming
# Tests all 9 combinations of client-server pairs (Java, C++, Rust)

set -e

# Source common utilities
source "$(dirname "$0")/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test configuration
TEST_PORT_BASE=50051
TEST_TIMEOUT=30
TEST_QUERY="test coffee maker"
TEST_ASIN="B000TEST123"
TEST_UNDERSTANDING="premium test coffee brewing equipment"

# Languages to test
LANGUAGES=("java" "cpp" "rust")

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to set test result
set_test_result() {
    local test_name="$1"
    local result="$2"
    echo "$test_name:$result" >> "/tmp/grpc_test_results_$$.tmp"
}

# Function to get test result
get_test_result() {
    local test_name="$1"
    if [ -f "/tmp/grpc_test_results_$$.tmp" ]; then
        grep "^$test_name:" "/tmp/grpc_test_results_$$.tmp" 2>/dev/null | cut -d: -f2- | tail -1
    fi
}



# Function to find available port
find_available_port() {
    local base_port="$1"
    local port="$base_port"
    
    while lsof -i ":$port" >/dev/null 2>&1; do
        port=$((port + 1))
    done
    
    echo "$port"
}

# Function to wait for server to start
wait_for_server() {
    local host="$1"
    local port="$2"
    local timeout="$3"
    local count=0
    
    while [ $count -lt "$timeout" ]; do
        if command_exists nc && nc -z "$host" "$port" 2>/dev/null; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    return 1
}

# Function to run server in background
start_server() {
    local language="$1"
    local port="$2"
    
    print_status "blue" "Starting $language server on port $port..."
    
    # Start server in background and capture PID
    "$SCRIPT_DIR/run-server.sh" "$language" "$port" >/dev/null 2>&1 &
    local server_pid=$!
    
    # Wait for server to start
    if wait_for_server "localhost" "$port" 10; then
        print_status "green" "$language server started (PID: $server_pid)"
        echo "$server_pid"
        return 0
    else
        print_status "red" "Failed to start $language server"
        kill "$server_pid" 2>/dev/null || true
        return 1
    fi
}

# Function to stop server
stop_server() {
    local server_pid="$1"
    local language="$2"
    
    if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
        print_status "blue" "Stopping $language server (PID: $server_pid)..."
        kill "$server_pid" 2>/dev/null || true
        sleep 2
        
        # Force kill if still running
        if kill -0 "$server_pid" 2>/dev/null; then
            kill -9 "$server_pid" 2>/dev/null || true
        fi
        
        print_status "green" "$language server stopped"
    fi
}

# Function to run client test
run_client_test() {
    local client_lang="$1"
    local server_host="$2"
    local server_port="$3"
    
    print_status "cyan" "Running $client_lang client test..."
    
    # Create temporary log file
    local log_file="/tmp/grpc_client_test_${client_lang}_$$.log"
    
    # Run client with timeout
    if timeout "$TEST_TIMEOUT" "$SCRIPT_DIR/run-client.sh" \
        "$client_lang" "$server_host" "$server_port" \
        "$TEST_QUERY" "$TEST_ASIN" "$TEST_UNDERSTANDING" \
        >"$log_file" 2>&1; then
        
        # Analyze log for expected patterns
        local success=true
        local messages=""
        
        # Check for basic success indicators
        if ! grep -q "AdsList" "$log_file" 2>/dev/null; then
            success=false
            messages="$messages; No AdsList received"
        fi
        
        # Check for version information (if available in logs)
        if grep -q "version" "$log_file" 2>/dev/null; then
            local versions=$(grep -o "version[[:space:]]*[0-9]" "$log_file" 2>/dev/null | wc -l)
            if [ "$versions" -lt 3 ]; then
                messages="$messages; Expected 3 versions, got $versions"
            fi
        fi
        
        # Check for error patterns
        if grep -qi "error\|exception\|failed" "$log_file" 2>/dev/null; then
            success=false
            messages="$messages; Errors found in output"
        fi
        
        if [ "$success" = true ]; then
            print_status "green" "$client_lang client test passed"
            rm -f "$log_file"
            return 0
        else
            print_status "red" "$client_lang client test failed:$messages"
            print_status "yellow" "Log saved to: $log_file"
            return 1
        fi
    else
        print_status "red" "$client_lang client test failed (timeout or error)"
        print_status "yellow" "Log saved to: $log_file"
        return 1
    fi
}

# Function to test client-server combination
test_combination() {
    local server_lang="$1"
    local client_lang="$2"
    local test_name="${server_lang}-server-${client_lang}-client"
    
    print_status "blue" "Testing: $test_name"
    echo "----------------------------------------"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Find available port
    local port
    port=$(find_available_port $TEST_PORT_BASE)
    
    # Start server
    local server_pid
    if server_pid=$(start_server "$server_lang" "$port"); then
        sleep 2  # Give server time to fully initialize
        
        # Run client test
        if run_client_test "$client_lang" "localhost" "$port"; then
            set_test_result "$test_name" "PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            print_status "green" "✅ $test_name: PASSED"
        else
            set_test_result "$test_name" "FAIL"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            print_status "red" "❌ $test_name: FAILED"
        fi
        
        # Stop server
        stop_server "$server_pid" "$server_lang"
    else
        set_test_result "$test_name" "FAIL (server start)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        print_status "red" "❌ $test_name: FAILED (could not start server)"
    fi
    
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    print_status "blue" "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for required tools
    if ! command_exists lsof; then
        missing_tools+=("lsof")
    fi
    
    if ! command_exists timeout; then
        missing_tools+=("timeout")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_status "red" "Missing required tools: ${missing_tools[*]}"
        print_status "yellow" "Please install the missing tools and try again"
        exit 1
    fi
    
    # Check if projects are built
    local missing_builds=()
    
    # Check Java
    if [ ! -f "$PROJECT_ROOT/java/pom.xml" ] || [ ! -d "$PROJECT_ROOT/java/target" ]; then
        missing_builds+=("Java")
    fi
    
    # Check C++
    if [ ! -f "$PROJECT_ROOT/cpp/build/libads_proto.a" ]; then
        missing_builds+=("C++")
    fi
    
    # Check Rust
    if [ ! -f "$PROJECT_ROOT/rust/Cargo.toml" ] || [ ! -d "$PROJECT_ROOT/rust/target" ]; then
        missing_builds+=("Rust")
    fi
    
    if [ ${#missing_builds[@]} -gt 0 ]; then
        print_status "yellow" "Some projects may not be built: ${missing_builds[*]}"
        print_status "blue" "Consider running './scripts/build-all.sh' first"
    fi
    
    print_status "green" "Prerequisites check completed"
}

# Function to print test summary
print_summary() {
    echo ""
    echo "=================================================="
    echo "INTEROPERABILITY TEST SUMMARY"
    echo "=================================================="
    
    print_status "blue" "Total tests: $TOTAL_TESTS"
    print_status "green" "Passed: $PASSED_TESTS"
    print_status "red" "Failed: $FAILED_TESTS"
    
    echo ""
    echo "Detailed Results:"
    echo "----------------------------------------"
    
    for server_lang in "${LANGUAGES[@]}"; do
        for client_lang in "${LANGUAGES[@]}"; do
            local test_name="${server_lang}-server-${client_lang}-client"
            local result
            result=$(get_test_result "$test_name")
            
            if [ "$result" = "PASS" ]; then
                print_status "green" "$test_name: $result"
            else
                print_status "red" "$test_name: $result"
            fi
        done
    done
    
    echo ""
    
    if [ "$FAILED_TESTS" -eq 0 ]; then
        print_status "green" "🎉 All interoperability tests passed!"
        return 0
    else
        print_status "red" "❌ Some tests failed. Check the logs above for details."
        return 1
    fi
}

# Function to run specific test
run_specific_test() {
    local server_lang="$1"
    local client_lang="$2"
    
    if [[ ! " ${LANGUAGES[*]} " =~ " $server_lang " ]]; then
        print_status "red" "Unknown server language: $server_lang"
        exit 1
    fi
    
    if [[ ! " ${LANGUAGES[*]} " =~ " $client_lang " ]]; then
        print_status "red" "Unknown client language: $client_lang"
        exit 1
    fi
    
    test_combination "$server_lang" "$client_lang"
    print_summary
}

# Function to run all tests
run_all_tests() {
    print_status "blue" "Running all interoperability tests..."
    print_status "blue" "Testing ${#LANGUAGES[@]}x${#LANGUAGES[@]} = $((${#LANGUAGES[@]} * ${#LANGUAGES[@]})) combinations"
    echo ""
    
    for server_lang in "${LANGUAGES[@]}"; do
        for client_lang in "${LANGUAGES[@]}"; do
            test_combination "$server_lang" "$client_lang"
        done
    done
    
    print_summary
}

# Main execution
main() {
    local action="${1:-all}"
    local server_lang="$2"
    local client_lang="$3"
    
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - Interoperability Tests"
    echo "=================================================="
    print_status "blue" "Project root: $PROJECT_ROOT"
    print_status "blue" "Test timeout: ${TEST_TIMEOUT}s"
    print_status "blue" "Languages: ${LANGUAGES[*]}"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    case "$action" in
        all)
            run_all_tests
            ;;
        test)
            if [ -z "$server_lang" ] || [ -z "$client_lang" ]; then
                print_status "red" "Server and client languages required for specific test"
                print_usage
                exit 1
            fi
            run_specific_test "$server_lang" "$client_lang"
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            print_status "red" "Unknown action: $action"
            print_usage
            exit 1
            ;;
    esac
}

# Print usage information
print_usage() {
    echo "Usage: $0 [ACTION] [SERVER_LANG] [CLIENT_LANG]"
    echo ""
    echo "ACTIONS:"
    echo "  all         - Run all interoperability tests (default)"
    echo "  test        - Run specific server-client combination"
    echo "  help        - Show this help message"
    echo ""
    echo "LANGUAGES:"
    echo "  java        - Java implementation"
    echo "  cpp         - C++ implementation"
    echo "  rust        - Rust implementation"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Run all 9 combinations"
    echo "  $0 test java rust     # Test Java server with Rust client"
    echo "  $0 test cpp java      # Test C++ server with Java client"
    echo ""
    echo "NOTES:"
    echo "  - Make sure all projects are built before running tests"
    echo "  - Tests will use ports starting from $TEST_PORT_BASE"
    echo "  - Each test has a timeout of ${TEST_TIMEOUT} seconds"
    echo "  - Failed test logs are saved in /tmp for debugging"
}

# Cleanup function for graceful shutdown
cleanup() {
    print_status "yellow" "Cleaning up..."
    
    # Kill any remaining server processes
    pkill -f "run-server.sh" 2>/dev/null || true
    pkill -f "ads_server\|ads-server\|AdsServer" 2>/dev/null || true
    
    # Clean up temporary files
    rm -f "/tmp/grpc_test_results_$$.tmp"
    
    exit 0
}

# Handle Ctrl+C gracefully
trap cleanup INT TERM

main "$@"
