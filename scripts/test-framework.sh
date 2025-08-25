#!/bin/bash

# Advanced test framework for gRPC bidirectional streaming cross-language validation
# Implements comprehensive message count verification, version ordering, and result validation

set -e

# Source common utilities
source "$(dirname "$0")/common.sh"

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

# Test results storage - compatible with older bash versions
if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
    declare -A TEST_RESULTS
    declare -A TEST_DETAILS
else
    # Use files for compatibility with older bash
    TEST_RESULTS_FILE="/tmp/grpc_test_results_$$.tmp"
    TEST_DETAILS_FILE="/tmp/grpc_test_details_$$.tmp"
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

set_test_detail() {
    local key="$1"
    local value="$2"
    if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
        TEST_DETAILS["$key"]="$value"
    else
        echo "$key=$value" >> "$TEST_DETAILS_FILE"
    fi
}

get_test_detail() {
    local key="$1"
    if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
        echo "${TEST_DETAILS[$key]}"
    else
        grep "^$key=" "$TEST_DETAILS_FILE" 2>/dev/null | cut -d= -f2- | tail -1
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

# Function to start server in background
start_server() {
    local language="$1"
    local port="$2"
    
    print_status "blue" "Starting $language server on port $port..."
    
    # Create server log file
    local server_log="/tmp/grpc_server_${language}_${port}_$$.log"
    
    # Start server in background and capture PID
    "$SCRIPT_DIR/run-server.sh" "$language" "$port" >"$server_log" 2>&1 &
    local server_pid=$!
    
    # Wait for server to start
    if wait_for_server "localhost" "$port" 10; then
        print_status "green" "$language server started (PID: $server_pid)"
        echo "$server_pid:$server_log"
        return 0
    else
        print_status "red" "Failed to start $language server"
        print_status "yellow" "Server log: $server_log"
        kill "$server_pid" 2>/dev/null || true
        return 1
    fi
}

# Function to stop server
stop_server() {
    local server_info="$1"
    local language="$2"
    
    local server_pid="${server_info%%:*}"
    local server_log="${server_info##*:}"
    
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
    
    # Clean up server log if no errors
    if [ -f "$server_log" ] && ! grep -qi "error\|exception\|failed" "$server_log" 2>/dev/null; then
        rm -f "$server_log"
    fi
}

# Function to parse client output for validation
parse_client_output() {
    local log_file="$1"
    local test_name="$2"
    
    # Initialize validation results
    local context_count=0
    local adslist_count=0
    local versions_received=()
    local final_version=""
    local has_ads=false
    local error_found=false
    
    # Parse log file for validation data
    if [ -f "$log_file" ]; then
        # Count Context messages sent
        context_count=$(grep -c "Sending Context\|Context sent\|context message" "$log_file" 2>/dev/null || echo "0")
        
        # Count AdsList messages received
        adslist_count=$(grep -c "Received AdsList\|AdsList received\|version" "$log_file" 2>/dev/null || echo "0")
        
        # Extract version numbers
        while IFS= read -r line; do
            if [[ "$line" =~ version[[:space:]]*[=:][[:space:]]*([0-9]+) ]]; then
                versions_received+=("${BASH_REMATCH[1]}")
            fi
        done < <(grep -i "version" "$log_file" 2>/dev/null || true)
        
        # Extract final version selected
        if grep -q "Final\|Selected\|Result" "$log_file" 2>/dev/null; then
            final_version=$(grep -i "final\|selected\|result" "$log_file" 2>/dev/null | \
                           grep -o "version[[:space:]]*[=:][[:space:]]*[0-9]" | \
                           tail -1 | grep -o "[0-9]" || echo "")
        fi
        
        # Check if ads were received
        if grep -q "ads\|Ad\|asin_id\|ad_id" "$log_file" 2>/dev/null; then
            has_ads=true
        fi
        
        # Check for errors
        if grep -qi "error\|exception\|failed\|timeout" "$log_file" 2>/dev/null; then
            error_found=true
        fi
    fi
    
    # Store detailed results
    set_test_detail "${test_name}_context_count" "$context_count"
    set_test_detail "${test_name}_adslist_count" "$adslist_count"
    set_test_detail "${test_name}_versions" "${versions_received[*]}"
    set_test_detail "${test_name}_final_version" "$final_version"
    set_test_detail "${test_name}_has_ads" "$has_ads"
    set_test_detail "${test_name}_error_found" "$error_found"
    
    # Return validation results as JSON-like string
    echo "context_count:$context_count,adslist_count:$adslist_count,versions:${versions_received[*]},final_version:$final_version,has_ads:$has_ads,error_found:$error_found"
}

# Function to validate test results
validate_test_results() {
    local test_name="$1"
    local validation_data="$2"
    
    local validation_errors=()
    local validation_warnings=()
    
    # Parse validation data
    local context_count=$(echo "$validation_data" | grep -o "context_count:[0-9]*" | cut -d: -f2)
    local adslist_count=$(echo "$validation_data" | grep -o "adslist_count:[0-9]*" | cut -d: -f2)
    local versions=$(echo "$validation_data" | grep -o "versions:[^,]*" | cut -d: -f2-)
    local final_version=$(echo "$validation_data" | grep -o "final_version:[0-9]*" | cut -d: -f2)
    local has_ads=$(echo "$validation_data" | grep -o "has_ads:[^,]*" | cut -d: -f2)
    local error_found=$(echo "$validation_data" | grep -o "error_found:[^,]*" | cut -d: -f2)
    
    # Requirement 3.1: Verify exactly 2 Context messages
    if [ "$context_count" != "2" ]; then
        validation_errors+=("Expected 2 Context messages, got $context_count")
    fi
    
    # Requirement 3.2: Verify exactly 3 AdsList messages
    if [ "$adslist_count" != "3" ]; then
        validation_errors+=("Expected 3 AdsList messages, got $adslist_count")
    fi
    
    # Requirement 5.4: Verify version ordering (1, 2, 3)
    if [ -n "$versions" ]; then
        local version_array=($versions)
        local expected_versions=("1" "2" "3")
        
        if [ ${#version_array[@]} -eq 3 ]; then
            for i in {0..2}; do
                if [ "${version_array[$i]}" != "${expected_versions[$i]}" ]; then
                    validation_errors+=("Version ordering incorrect: expected ${expected_versions[*]}, got ${version_array[*]}")
                    break
                fi
            done
        else
            validation_warnings+=("Incomplete version sequence: got ${version_array[*]}")
        fi
    else
        validation_warnings+=("No version information found in output")
    fi
    
    # Verify final result selection
    if [ -n "$final_version" ]; then
        if [[ ! "$final_version" =~ ^[1-3]$ ]]; then
            validation_warnings+=("Unexpected final version: $final_version")
        fi
    else
        validation_warnings+=("No final version selection found")
    fi
    
    # Verify ads were received
    if [ "$has_ads" != "true" ]; then
        validation_errors+=("No ads found in response")
    fi
    
    # Check for errors
    if [ "$error_found" = "true" ]; then
        validation_warnings+=("Errors found in client output")
    fi
    
    # Determine overall result
    local result="PASS"
    if [ ${#validation_errors[@]} -gt 0 ]; then
        result="FAIL"
    elif [ ${#validation_warnings[@]} -gt 0 ]; then
        result="PASS_WITH_WARNINGS"
    fi
    
    # Store validation details
    set_test_detail "${test_name}_validation_errors" "${validation_errors[*]}"
    set_test_detail "${test_name}_validation_warnings" "${validation_warnings[*]}"
    set_test_detail "${test_name}_validation_result" "$result"
    
    echo "$result"
}

# Function to run enhanced client test with validation
run_enhanced_client_test() {
    local client_lang="$1"
    local server_host="$2"
    local server_port="$3"
    local test_name="$4"
    
    print_status "cyan" "Running enhanced $client_lang client test..."
    
    # Create temporary log file
    local log_file="/tmp/grpc_client_test_${client_lang}_${test_name}_$$.log"
    
    # Run client with timeout and enhanced logging
    if timeout "$TEST_TIMEOUT" "$SCRIPT_DIR/run-client.sh" \
        "$client_lang" "$server_host" "$server_port" \
        "$TEST_QUERY" "$TEST_ASIN" "$TEST_UNDERSTANDING" \
        >"$log_file" 2>&1; then
        
        # Parse client output for validation
        local validation_data
        validation_data=$(parse_client_output "$log_file" "$test_name")
        
        # Validate test results
        local validation_result
        validation_result=$(validate_test_results "$test_name" "$validation_data")
        
        case "$validation_result" in
            "PASS")
                print_status "green" "$client_lang client test passed"
                rm -f "$log_file"
                return 0
                ;;
            "PASS_WITH_WARNINGS")
                print_status "yellow" "$client_lang client test passed with warnings"
                local warnings
                warnings=$(get_test_detail "${test_name}_validation_warnings")
                print_status "yellow" "Warnings: $warnings"
                print_status "blue" "Log saved to: $log_file"
                return 0
                ;;
            "FAIL")
                print_status "red" "$client_lang client test failed"
                local errors
                errors=$(get_test_detail "${test_name}_validation_errors")
                print_status "red" "Errors: $errors"
                print_status "yellow" "Log saved to: $log_file"
                return 1
                ;;
        esac
    else
        print_status "red" "$client_lang client test failed (timeout or execution error)"
        print_status "yellow" "Log saved to: $log_file"
        return 1
    fi
}

# Function to test client-server combination with enhanced validation
test_combination_enhanced() {
    local server_lang="$1"
    local client_lang="$2"
    local test_name="${server_lang}-server-${client_lang}-client"
    
    print_status "blue" "Testing: $test_name (Enhanced Validation)"
    echo "----------------------------------------"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Find available port
    local port
    port=$(find_available_port $TEST_PORT_BASE)
    
    # Start server
    local server_info
    if server_info=$(start_server "$server_lang" "$port"); then
        sleep 2  # Give server time to fully initialize
        
        # Run enhanced client test
        if run_enhanced_client_test "$client_lang" "localhost" "$port" "$test_name"; then
            set_test_result "$test_name" "PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            print_status "green" "✅ $test_name: PASSED"
        else
            set_test_result "$test_name" "FAIL"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            print_status "red" "❌ $test_name: FAILED"
        fi
        
        # Stop server
        stop_server "$server_info" "$server_lang"
    else
        set_test_result "$test_name" "FAIL (server start)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        print_status "red" "❌ $test_name: FAILED (could not start server)"
    fi
    
    echo ""
}

# Function to print detailed test summary
print_detailed_summary() {
    echo ""
    echo "=================================================="
    echo "ENHANCED INTEROPERABILITY TEST SUMMARY"
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
            
            # Print validation details if available
            local context_count
            local adslist_count
            local versions
            local final_version
            context_count=$(get_test_detail "${test_name}_context_count")
            adslist_count=$(get_test_detail "${test_name}_adslist_count")
            versions=$(get_test_detail "${test_name}_versions")
            final_version=$(get_test_detail "${test_name}_final_version")
            
            if [ -n "$context_count" ]; then
                echo "    Context messages: $context_count, AdsList messages: $adslist_count"
                echo "    Versions received: [$versions], Final version: $final_version"
            fi
            
            local errors
            local warnings
            errors=$(get_test_detail "${test_name}_validation_errors")
            warnings=$(get_test_detail "${test_name}_validation_warnings")
            
            if [ -n "$errors" ]; then
                echo "    Errors: $errors"
            fi
            
            if [ -n "$warnings" ]; then
                echo "    Warnings: $warnings"
            fi
            
            echo ""
        done
    done
    
    echo "Requirements Validation Summary:"
    echo "----------------------------------------"
    
    # Analyze overall compliance
    local context_compliant=0
    local adslist_compliant=0
    local version_compliant=0
    local total_analyzed=0
    
    for server_lang in "${LANGUAGES[@]}"; do
        for client_lang in "${LANGUAGES[@]}"; do
            local test_name="${server_lang}-server-${client_lang}-client"
            local context_count
            local adslist_count
            local versions
            context_count=$(get_test_detail "${test_name}_context_count")
            adslist_count=$(get_test_detail "${test_name}_adslist_count")
            versions=$(get_test_detail "${test_name}_versions")
            
            if [ -n "$context_count" ]; then
                total_analyzed=$((total_analyzed + 1))
                
                if [ "$context_count" = "2" ]; then
                    context_compliant=$((context_compliant + 1))
                fi
                
                if [ "$adslist_count" = "3" ]; then
                    adslist_compliant=$((adslist_compliant + 1))
                fi
                
                if [ "$versions" = "1 2 3" ]; then
                    version_compliant=$((version_compliant + 1))
                fi
            fi
        done
    done
    
    if [ $total_analyzed -gt 0 ]; then
        print_status "purple" "Requirement 3.1 (2 Context messages): $context_compliant/$total_analyzed compliant"
        print_status "purple" "Requirement 3.2 (3 AdsList messages): $adslist_compliant/$total_analyzed compliant"
        print_status "purple" "Requirement 5.4 (Version ordering 1,2,3): $version_compliant/$total_analyzed compliant"
    fi
    
    echo ""
    
    if [ "$FAILED_TESTS" -eq 0 ]; then
        print_status "green" "🎉 All enhanced interoperability tests passed!"
        return 0
    else
        print_status "red" "❌ Some tests failed. Check the detailed results above."
        return 1
    fi
}

# Function to run all enhanced tests
run_all_enhanced_tests() {
    print_status "blue" "Running all enhanced interoperability tests..."
    print_status "blue" "Testing ${#LANGUAGES[@]}x${#LANGUAGES[@]} = $((${#LANGUAGES[@]} * ${#LANGUAGES[@]})) combinations with validation"
    echo ""
    
    for server_lang in "${LANGUAGES[@]}"; do
        for client_lang in "${LANGUAGES[@]}"; do
            test_combination_enhanced "$server_lang" "$client_lang"
        done
    done
    
    print_detailed_summary
}

# Function to run specific enhanced test
run_specific_enhanced_test() {
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
    
    test_combination_enhanced "$server_lang" "$client_lang"
    print_detailed_summary
}

# Function to check prerequisites
check_prerequisites() {
    print_status "blue" "Checking prerequisites for enhanced testing..."
    
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
    if [ ! -d "$PROJECT_ROOT/cpp/build" ]; then
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

# Main execution
main() {
    local action="${1:-all}"
    local server_lang="$2"
    local client_lang="$3"
    
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - Enhanced Test Framework"
    echo "=================================================="
    print_status "blue" "Project root: $PROJECT_ROOT"
    print_status "blue" "Test timeout: ${TEST_TIMEOUT}s"
    print_status "blue" "Languages: ${LANGUAGES[*]}"
    print_status "purple" "Enhanced validation: Message counts, version ordering, result validation"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    case "$action" in
        all)
            run_all_enhanced_tests
            ;;
        test)
            if [ -z "$server_lang" ] || [ -z "$client_lang" ]; then
                print_status "red" "Server and client languages required for specific test"
                print_usage
                exit 1
            fi
            run_specific_enhanced_test "$server_lang" "$client_lang"
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
    echo "  all         - Run all enhanced interoperability tests (default)"
    echo "  test        - Run specific server-client combination with validation"
    echo "  help        - Show this help message"
    echo ""
    echo "LANGUAGES:"
    echo "  java        - Java implementation"
    echo "  cpp         - C++ implementation"
    echo "  rust        - Rust implementation"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Run all 9 combinations with enhanced validation"
    echo "  $0 test java rust     # Test Java server with Rust client (enhanced)"
    echo "  $0 test cpp java      # Test C++ server with Java client (enhanced)"
    echo ""
    echo "ENHANCED VALIDATION FEATURES:"
    echo "  - Message count verification (2 Context, 3 AdsList)"
    echo "  - Version ordering validation (1, 2, 3)"
    echo "  - Final result selection verification"
    echo "  - Detailed error and warning reporting"
    echo "  - Requirements compliance tracking"
    echo ""
    echo "NOTES:"
    echo "  - Make sure all projects are built before running tests"
    echo "  - Tests will use ports starting from $TEST_PORT_BASE"
    echo "  - Each test has a timeout of ${TEST_TIMEOUT} seconds"
    echo "  - Failed test logs are saved in /tmp for debugging"
    echo "  - Enhanced validation provides detailed compliance reporting"
}

# Cleanup function for graceful shutdown
cleanup() {
    print_status "yellow" "Cleaning up enhanced test framework..."
    
    # Kill any remaining server processes
    pkill -f "run-server.sh" 2>/dev/null || true
    pkill -f "ads_server\|ads-server\|AdsServer" 2>/dev/null || true
    
    # Clean up temporary files (keep failed test logs)
    if [ "$USE_ASSOCIATIVE_ARRAYS" = false ]; then
        rm -f "$TEST_RESULTS_FILE" "$TEST_DETAILS_FILE"
    fi
    
    exit 0
}

# Handle Ctrl+C gracefully
trap cleanup INT TERM

main "$@"
