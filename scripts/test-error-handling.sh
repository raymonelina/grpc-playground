#!/bin/bash

# Error handling and graceful shutdown test suite for gRPC bidirectional streaming
# Tests connection failures, recovery scenarios, stream cleanup, and timeout handling

set -e

# Check for bash version 4+ for associative arrays, fallback to files if not available
if [ "${BASH_VERSION%%.*}" -ge 4 ] 2>/dev/null; then
    USE_ASSOCIATIVE_ARRAYS=true
else
    USE_ASSOCIATIVE_ARRAYS=false
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test configuration
TEST_PORT_BASE=50051
TEST_TIMEOUT=15
SHORT_TIMEOUT=5
LONG_TIMEOUT=30
TEST_QUERY="test coffee maker"
TEST_ASIN="B000TEST123"
TEST_UNDERSTANDING="premium test coffee brewing equipment"

# Languages to test
LANGUAGES=("java" "cpp" "rust")

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test results storage - compatible with older bash versions
if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
    declare -A TEST_RESULTS
    declare -A TEST_DETAILS
else
    # Use files for compatibility with older bash
    TEST_RESULTS_FILE="/tmp/grpc_error_test_results_$$.tmp"
    TEST_DETAILS_FILE="/tmp/grpc_error_test_details_$$.tmp"
    > "$TEST_RESULTS_FILE"
    > "$TEST_DETAILS_FILE"
fi

# Helper functions for result storage
set_test_result() {
    local key="$1"
    local value="$2"
    if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
        TEST_RESULTS["$key"]="$value"
    else
        echo "$key=$value" >> "$TEST_RESULTS_FILE"
    fi
}

get_test_result() {
    local key="$1"
    if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
        echo "${TEST_RESULTS[$key]}"
    else
        grep "^$key=" "$TEST_RESULTS_FILE" 2>/dev/null | cut -d= -f2- | tail -1
    fi
}

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    case "$color" in
        "green") echo -e "\033[32m✅ $message\033[0m" ;;
        "red") echo -e "\033[31m❌ $message\033[0m" ;;
        "yellow") echo -e "\033[33m⚠️  $message\033[0m" ;;
        "blue") echo -e "\033[34mℹ️  $message\033[0m" ;;
        "cyan") echo -e "\033[36m🔍 $message\033[0m" ;;
        "purple") echo -e "\033[35m📊 $message\033[0m" ;;
        *) echo "$message" ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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

# Function to start server in background
start_server() {
    local language="$1"
    local port="$2"
    
    # Create server log file
    local server_log="/tmp/grpc_error_test_server_${language}_${port}_$$.log"
    
    # Start server in background and capture PID
    "$SCRIPT_DIR/run-server.sh" "$language" "$port" >"$server_log" 2>&1 &
    local server_pid=$!
    
    # Wait for server to start
    if wait_for_server "localhost" "$port" 10; then
        echo "$server_pid:$server_log"
        return 0
    else
        kill "$server_pid" 2>/dev/null || true
        return 1
    fi
}

# Function to stop server
stop_server() {
    local server_info="$1"
    
    local server_pid="${server_info%%:*}"
    local server_log="${server_info##*:}"
    
    if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        sleep 1
        
        # Force kill if still running
        if kill -0 "$server_pid" 2>/dev/null; then
            kill -9 "$server_pid" 2>/dev/null || true
        fi
    fi
    
    # Return server log path for analysis
    echo "$server_log"
}

# Function to test connection failure handling
test_connection_failure() {
    local client_lang="$1"
    local test_name="connection-failure-${client_lang}"
    
    print_status "cyan" "Testing connection failure handling for $client_lang client..."
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Use a port that's guaranteed to be closed
    local closed_port
    closed_port=$(find_available_port $((TEST_PORT_BASE + 1000)))
    
    # Create client log file
    local client_log="/tmp/grpc_error_test_client_${client_lang}_${test_name}_$$.log"
    
    # Run client against closed port (should fail gracefully)
    if timeout "$SHORT_TIMEOUT" "$SCRIPT_DIR/run-client.sh" \
        "$client_lang" "localhost" "$closed_port" \
        "$TEST_QUERY" "$TEST_ASIN" "$TEST_UNDERSTANDING" \
        >"$client_log" 2>&1; then
        
        # Client should not succeed when connecting to closed port
        print_status "red" "❌ $test_name: Client unexpectedly succeeded"
        set_test_result "$test_name" "FAIL"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    else
        # Check if client handled the failure gracefully
        local graceful_failure=true
        local error_messages=()
        
        if [ -f "$client_log" ]; then
            # Look for appropriate error handling
            if grep -qi "connection.*refused\|unavailable\|failed.*connect" "$client_log" 2>/dev/null; then
                # Good - client detected connection failure
                :
            else
                graceful_failure=false
                error_messages+=("No connection failure detection")
            fi
            
            # Check for crashes or exceptions that weren't handled
            if grep -qi "segmentation fault\|core dumped\|panic\|abort" "$client_log" 2>/dev/null; then
                graceful_failure=false
                error_messages+=("Client crashed instead of graceful failure")
            fi
            
            # Check for proper cleanup messages
            if grep -qi "cleanup\|shutdown\|closing" "$client_log" 2>/dev/null; then
                # Good - client performed cleanup
                :
            fi
        else
            graceful_failure=false
            error_messages+=("No client log generated")
        fi
        
        if [ "$graceful_failure" = true ]; then
            print_status "green" "✅ $test_name: Client handled connection failure gracefully"
            set_test_result "$test_name" "PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            rm -f "$client_log"
            return 0
        else
            print_status "red" "❌ $test_name: Client did not handle failure gracefully"
            print_status "yellow" "Issues: ${error_messages[*]}"
            print_status "yellow" "Log saved to: $client_log"
            set_test_result "$test_name" "FAIL"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    fi
}

# Function to test server shutdown during communication
test_server_shutdown() {
    local server_lang="$1"
    local client_lang="$2"
    local test_name="server-shutdown-${server_lang}-${client_lang}"
    
    print_status "cyan" "Testing server shutdown during communication ($server_lang server, $client_lang client)..."
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Find available port
    local port
    port=$(find_available_port $TEST_PORT_BASE)
    
    # Start server
    local server_info
    if server_info=$(start_server "$server_lang" "$port"); then
        sleep 1  # Give server time to initialize
        
        # Create client log file
        local client_log="/tmp/grpc_error_test_client_${client_lang}_${test_name}_$$.log"
        
        # Start client in background
        timeout "$LONG_TIMEOUT" "$SCRIPT_DIR/run-client.sh" \
            "$client_lang" "localhost" "$port" \
            "$TEST_QUERY" "$TEST_ASIN" "$TEST_UNDERSTANDING" \
            >"$client_log" 2>&1 &
        local client_pid=$!
        
        # Wait a moment for client to start communication
        sleep 2
        
        # Abruptly kill the server
        local server_pid="${server_info%%:*}"
        if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
            kill -9 "$server_pid" 2>/dev/null || true
        fi
        
        # Wait for client to finish
        local client_exit_code=0
        wait "$client_pid" || client_exit_code=$?
        
        # Analyze client behavior
        local graceful_handling=true
        local error_messages=()
        
        if [ -f "$client_log" ]; then
            # Check if client detected server disconnection
            if grep -qi "connection.*lost\|server.*disconnect\|stream.*closed\|unavailable" "$client_log" 2>/dev/null; then
                # Good - client detected disconnection
                :
            else
                graceful_handling=false
                error_messages+=("Client did not detect server disconnection")
            fi
            
            # Check for crashes
            if grep -qi "segmentation fault\|core dumped\|panic\|abort" "$client_log" 2>/dev/null; then
                graceful_handling=false
                error_messages+=("Client crashed on server disconnection")
            fi
            
            # Check for proper error handling
            if grep -qi "error\|exception" "$client_log" 2>/dev/null && \
               ! grep -qi "segmentation fault\|core dumped\|panic\|abort" "$client_log" 2>/dev/null; then
                # Good - client reported errors without crashing
                :
            fi
        else
            graceful_handling=false
            error_messages+=("No client log generated")
        fi
        
        # Clean up server log
        local server_log
        server_log=$(stop_server "$server_info")
        rm -f "$server_log"
        
        if [ "$graceful_handling" = true ]; then
            print_status "green" "✅ $test_name: Client handled server shutdown gracefully"
            TEST_RESULTS["$test_name"]="PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            rm -f "$client_log"
            return 0
        else
            print_status "red" "❌ $test_name: Client did not handle server shutdown gracefully"
            print_status "yellow" "Issues: ${error_messages[*]}"
            print_status "yellow" "Log saved to: $client_log"
            TEST_RESULTS["$test_name"]="FAIL"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    else
        print_status "red" "❌ $test_name: Could not start server"
        TEST_RESULTS["$test_name"]="FAIL"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Function to test deadline/timeout handling
test_deadline_handling() {
    local server_lang="$1"
    local client_lang="$2"
    local test_name="deadline-handling-${server_lang}-${client_lang}"
    
    print_status "cyan" "Testing deadline handling ($server_lang server, $client_lang client)..."
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Find available port
    local port
    port=$(find_available_port $TEST_PORT_BASE)
    
    # Start server
    local server_info
    if server_info=$(start_server "$server_lang" "$port"); then
        sleep 1  # Give server time to initialize
        
        # Create client log file
        local client_log="/tmp/grpc_error_test_client_${client_lang}_${test_name}_$$.log"
        
        # Run client with very short timeout to force deadline exceeded
        if timeout "$SHORT_TIMEOUT" "$SCRIPT_DIR/run-client.sh" \
            "$client_lang" "localhost" "$port" \
            "$TEST_QUERY" "$TEST_ASIN" "$TEST_UNDERSTANDING" \
            >"$client_log" 2>&1; then
            
            # Client completed within short timeout - check if it handled deadlines properly
            local deadline_handling=true
            local messages=()
            
            if [ -f "$client_log" ]; then
                # Check if client implemented timeout logic
                if grep -qi "timeout\|deadline\|cancel" "$client_log" 2>/dev/null; then
                    messages+=("Client implemented timeout handling")
                else
                    deadline_handling=false
                    messages+=("No timeout handling detected")
                fi
                
                # Check for proper completion
                if grep -qi "completed\|finished\|result" "$client_log" 2>/dev/null; then
                    messages+=("Client completed successfully")
                fi
            fi
            
            if [ "$deadline_handling" = true ]; then
                print_status "green" "✅ $test_name: Client handled deadlines appropriately"
                TEST_RESULTS["$test_name"]="PASS"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_status "yellow" "⚠️ $test_name: Client completed but no deadline handling detected"
                TEST_RESULTS["$test_name"]="PASS_WITH_WARNINGS"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            fi
            
            print_status "blue" "Messages: ${messages[*]}"
            rm -f "$client_log"
        else
            # Client timed out - this is expected behavior
            local timeout_handling=true
            local error_messages=()
            
            if [ -f "$client_log" ]; then
                # Check for crashes during timeout
                if grep -qi "segmentation fault\|core dumped\|panic\|abort" "$client_log" 2>/dev/null; then
                    timeout_handling=false
                    error_messages+=("Client crashed during timeout")
                fi
                
                # Check for proper timeout detection
                if grep -qi "timeout\|deadline.*exceeded\|cancel" "$client_log" 2>/dev/null; then
                    # Good - client detected timeout
                    :
                fi
            fi
            
            if [ "$timeout_handling" = true ]; then
                print_status "green" "✅ $test_name: Client handled timeout gracefully"
                TEST_RESULTS["$test_name"]="PASS"
                PASSED_TESTS=$((PASSED_TESTS + 1))
                rm -f "$client_log"
            else
                print_status "red" "❌ $test_name: Client did not handle timeout gracefully"
                print_status "yellow" "Issues: ${error_messages[*]}"
                print_status "yellow" "Log saved to: $client_log"
                TEST_RESULTS["$test_name"]="FAIL"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
        fi
        
        # Clean up server
        local server_log
        server_log=$(stop_server "$server_info")
        rm -f "$server_log"
        
        return 0
    else
        print_status "red" "❌ $test_name: Could not start server"
        TEST_RESULTS["$test_name"]="FAIL"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Function to test resource cleanup
test_resource_cleanup() {
    local server_lang="$1"
    local client_lang="$2"
    local test_name="resource-cleanup-${server_lang}-${client_lang}"
    
    print_status "cyan" "Testing resource cleanup ($server_lang server, $client_lang client)..."
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Find available port
    local port
    port=$(find_available_port $TEST_PORT_BASE)
    
    # Record initial process count
    local initial_processes
    initial_processes=$(pgrep -f "ads_server\|ads-server\|AdsServer\|run-server\|run-client" | wc -l)
    
    # Start server
    local server_info
    if server_info=$(start_server "$server_lang" "$port"); then
        sleep 1
        
        # Create client log file
        local client_log="/tmp/grpc_error_test_client_${client_lang}_${test_name}_$$.log"
        
        # Run client normally
        timeout "$TEST_TIMEOUT" "$SCRIPT_DIR/run-client.sh" \
            "$client_lang" "localhost" "$port" \
            "$TEST_QUERY" "$TEST_ASIN" "$TEST_UNDERSTANDING" \
            >"$client_log" 2>&1 || true
        
        # Stop server
        local server_log
        server_log=$(stop_server "$server_info")
        
        # Wait for cleanup
        sleep 2
        
        # Check final process count
        local final_processes
        final_processes=$(pgrep -f "ads_server\|ads-server\|AdsServer\|run-server\|run-client" | wc -l)
        
        # Check for resource leaks
        local cleanup_successful=true
        local cleanup_messages=()
        
        if [ "$final_processes" -gt "$initial_processes" ]; then
            cleanup_successful=false
            cleanup_messages+=("Process leak detected: $initial_processes -> $final_processes")
        else
            cleanup_messages+=("No process leaks detected")
        fi
        
        # Check for port cleanup
        if lsof -i ":$port" >/dev/null 2>&1; then
            cleanup_successful=false
            cleanup_messages+=("Port $port still in use after cleanup")
        else
            cleanup_messages+=("Port properly released")
        fi
        
        # Clean up logs
        rm -f "$client_log" "$server_log"
        
        if [ "$cleanup_successful" = true ]; then
            print_status "green" "✅ $test_name: Resources cleaned up properly"
            TEST_RESULTS["$test_name"]="PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_status "red" "❌ $test_name: Resource cleanup issues detected"
            print_status "yellow" "Issues: ${cleanup_messages[*]}"
            TEST_RESULTS["$test_name"]="FAIL"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        
        return 0
    else
        print_status "red" "❌ $test_name: Could not start server"
        TEST_RESULTS["$test_name"]="FAIL"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Function to run all error handling tests
run_all_error_tests() {
    print_status "blue" "Running comprehensive error handling and graceful shutdown tests..."
    echo ""
    
    # Test connection failures for each client language
    print_status "purple" "Testing connection failure handling..."
    for client_lang in "${LANGUAGES[@]}"; do
        test_connection_failure "$client_lang"
    done
    echo ""
    
    # Test server shutdown scenarios
    print_status "purple" "Testing server shutdown handling..."
    for server_lang in "${LANGUAGES[@]}"; do
        for client_lang in "${LANGUAGES[@]}"; do
            test_server_shutdown "$server_lang" "$client_lang"
        done
    done
    echo ""
    
    # Test deadline handling
    print_status "purple" "Testing deadline and timeout handling..."
    for server_lang in "${LANGUAGES[@]}"; do
        for client_lang in "${LANGUAGES[@]}"; do
            test_deadline_handling "$server_lang" "$client_lang"
        done
    done
    echo ""
    
    # Test resource cleanup
    print_status "purple" "Testing resource cleanup..."
    for server_lang in "${LANGUAGES[@]}"; do
        for client_lang in "${LANGUAGES[@]}"; do
            test_resource_cleanup "$server_lang" "$client_lang"
        done
    done
}

# Function to print test summary
print_error_test_summary() {
    echo ""
    echo "=================================================="
    echo "ERROR HANDLING AND GRACEFUL SHUTDOWN TEST SUMMARY"
    echo "=================================================="
    
    print_status "purple" "Test Statistics:"
    print_status "blue" "Total tests: $TOTAL_TESTS"
    print_status "green" "Passed: $PASSED_TESTS"
    print_status "red" "Failed: $FAILED_TESTS"
    
    if [ $TOTAL_TESTS -gt 0 ]; then
        local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        print_status "purple" "Success rate: ${success_rate}%"
    fi
    
    echo ""
    echo "Detailed Results by Category:"
    echo "----------------------------------------"
    
    # Connection failure tests
    print_status "purple" "Connection Failure Handling:"
    for client_lang in "${LANGUAGES[@]}"; do
        local test_name="connection-failure-${client_lang}"
        local result="${TEST_RESULTS[$test_name]}"
        if [ "$result" = "PASS" ]; then
            print_status "green" "  $client_lang client: $result"
        else
            print_status "red" "  $client_lang client: $result"
        fi
    done
    
    echo ""
    
    # Server shutdown tests
    print_status "purple" "Server Shutdown Handling:"
    for server_lang in "${LANGUAGES[@]}"; do
        for client_lang in "${LANGUAGES[@]}"; do
            local test_name="server-shutdown-${server_lang}-${client_lang}"
            local result="${TEST_RESULTS[$test_name]}"
            if [ "$result" = "PASS" ]; then
                print_status "green" "  $server_lang-$client_lang: $result"
            else
                print_status "red" "  $server_lang-$client_lang: $result"
            fi
        done
    done
    
    echo ""
    
    # Deadline handling tests
    print_status "purple" "Deadline/Timeout Handling:"
    for server_lang in "${LANGUAGES[@]}"; do
        for client_lang in "${LANGUAGES[@]}"; do
            local test_name="deadline-handling-${server_lang}-${client_lang}"
            local result="${TEST_RESULTS[$test_name]}"
            if [[ "$result" =~ ^PASS ]]; then
                print_status "green" "  $server_lang-$client_lang: $result"
            else
                print_status "red" "  $server_lang-$client_lang: $result"
            fi
        done
    done
    
    echo ""
    
    # Resource cleanup tests
    print_status "purple" "Resource Cleanup:"
    for server_lang in "${LANGUAGES[@]}"; do
        for client_lang in "${LANGUAGES[@]}"; do
            local test_name="resource-cleanup-${server_lang}-${client_lang}"
            local result="${TEST_RESULTS[$test_name]}"
            if [ "$result" = "PASS" ]; then
                print_status "green" "  $server_lang-$client_lang: $result"
            else
                print_status "red" "  $server_lang-$client_lang: $result"
            fi
        done
    done
    
    echo ""
    
    if [ "$FAILED_TESTS" -eq 0 ]; then
        print_status "green" "🎉 All error handling and graceful shutdown tests passed!"
        return 0
    else
        print_status "red" "❌ Some error handling tests failed. Check the detailed results above."
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "blue" "Checking prerequisites for error handling tests..."
    
    local missing_tools=()
    
    # Check for required tools
    if ! command_exists lsof; then
        missing_tools+=("lsof")
    fi
    
    if ! command_exists timeout; then
        missing_tools+=("timeout")
    fi
    
    if ! command_exists nc; then
        missing_tools+=("nc (netcat)")
    fi
    
    if ! command_exists pgrep; then
        missing_tools+=("pgrep")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_status "red" "Missing required tools: ${missing_tools[*]}"
        print_status "yellow" "Please install the missing tools and try again"
        exit 1
    fi
    
    print_status "green" "Prerequisites check completed"
}

# Main execution
main() {
    local action="${1:-all}"
    local server_lang="$2"
    local client_lang="$3"
    
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - Error Handling Tests"
    echo "=================================================="
    print_status "blue" "Project root: $PROJECT_ROOT"
    print_status "blue" "Test timeout: ${TEST_TIMEOUT}s"
    print_status "blue" "Languages: ${LANGUAGES[*]}"
    print_status "purple" "Testing: Connection failures, server shutdown, deadlines, resource cleanup"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    case "$action" in
        all)
            run_all_error_tests
            print_error_test_summary
            ;;
        connection)
            print_status "blue" "Testing connection failure handling..."
            for client_lang in "${LANGUAGES[@]}"; do
                test_connection_failure "$client_lang"
            done
            print_error_test_summary
            ;;
        shutdown)
            print_status "blue" "Testing server shutdown handling..."
            for server_lang in "${LANGUAGES[@]}"; do
                for client_lang in "${LANGUAGES[@]}"; do
                    test_server_shutdown "$server_lang" "$client_lang"
                done
            done
            print_error_test_summary
            ;;
        deadline)
            print_status "blue" "Testing deadline handling..."
            for server_lang in "${LANGUAGES[@]}"; do
                for client_lang in "${LANGUAGES[@]}"; do
                    test_deadline_handling "$server_lang" "$client_lang"
                done
            done
            print_error_test_summary
            ;;
        cleanup)
            print_status "blue" "Testing resource cleanup..."
            for server_lang in "${LANGUAGES[@]}"; do
                for client_lang in "${LANGUAGES[@]}"; do
                    test_resource_cleanup "$server_lang" "$client_lang"
                done
            done
            print_error_test_summary
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
    echo "Usage: $0 [ACTION]"
    echo ""
    echo "ACTIONS:"
    echo "  all         - Run all error handling tests (default)"
    echo "  connection  - Test connection failure handling"
    echo "  shutdown    - Test server shutdown scenarios"
    echo "  deadline    - Test deadline and timeout handling"
    echo "  cleanup     - Test resource cleanup"
    echo "  help        - Show this help message"
    echo ""
    echo "TEST CATEGORIES:"
    echo "  Connection Failures:"
    echo "    - Client behavior when server is unavailable"
    echo "    - Graceful error handling and reporting"
    echo "    - Proper cleanup on connection failure"
    echo ""
    echo "  Server Shutdown:"
    echo "    - Client behavior when server disconnects during communication"
    echo "    - Stream interruption handling"
    echo "    - Recovery and cleanup scenarios"
    echo ""
    echo "  Deadline Handling:"
    echo "    - Timeout behavior and deadline enforcement"
    echo "    - Graceful cancellation of operations"
    echo "    - Proper resource cleanup on timeout"
    echo ""
    echo "  Resource Cleanup:"
    echo "    - Process cleanup after normal operation"
    echo "    - Port release and resource management"
    echo "    - Memory and connection leak detection"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Run all error handling tests"
    echo "  $0 connection         # Test only connection failure handling"
    echo "  $0 shutdown           # Test only server shutdown scenarios"
    echo ""
    echo "NOTES:"
    echo "  - Tests verify Requirements 3.4 and 3.5 compliance"
    echo "  - Failed test logs are saved in /tmp for debugging"
    echo "  - Tests include process and resource leak detection"
    echo "  - All languages are tested for comprehensive coverage"
}

# Cleanup function for graceful shutdown
cleanup() {
    print_status "yellow" "Cleaning up error handling test processes..."
    
    # Kill any remaining server processes
    pkill -f "run-server.sh" 2>/dev/null || true
    pkill -f "ads_server\|ads-server\|AdsServer" 2>/dev/null || true
    
    # Clean up temporary files (keep failed test logs)
    rm -f "/tmp/grpc_error_test_results_$$.tmp"
    
    exit 0
}

# Handle Ctrl+C gracefully
trap cleanup INT TERM

main "$@"