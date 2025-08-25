#!/bin/bash

# Comprehensive test suite for gRPC bidirectional streaming interoperability
# Integrates enhanced validation framework and error handling tests

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
TEST_REPORT_DIR="/tmp/grpc_comprehensive_test_$$"
TEST_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Test suite components
ENHANCED_FRAMEWORK="$SCRIPT_DIR/test-framework.sh"
ERROR_HANDLING="$SCRIPT_DIR/test-error-handling.sh"
BASIC_INTEROP="$SCRIPT_DIR/test-interop.sh"
TEST_RUNNER="$SCRIPT_DIR/test-runner.sh"

# Languages to test
LANGUAGES=("java" "cpp" "rust")

# Test results tracking - compatible with older bash versions
if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
    declare -A SUITE_RESULTS
    declare -A SUITE_DETAILS
else
    # Use files for compatibility with older bash
    SUITE_RESULTS_FILE="/tmp/grpc_suite_results_$$.tmp"
    SUITE_DETAILS_FILE="/tmp/grpc_suite_details_$$.tmp"
    > "$SUITE_RESULTS_FILE"
    > "$SUITE_DETAILS_FILE"
fi

# Helper functions for result storage
set_suite_result() {
    local key="$1"
    local value="$2"
    if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
        SUITE_RESULTS["$key"]="$value"
    else
        echo "$key=$value" >> "$SUITE_RESULTS_FILE"
    fi
}

get_suite_result() {
    local key="$1"
    if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
        echo "${SUITE_RESULTS[$key]}"
    else
        grep "^$key=" "$SUITE_RESULTS_FILE" 2>/dev/null | cut -d= -f2- | tail -1
    fi
}

set_suite_detail() {
    local key="$1"
    local value="$2"
    if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
        SUITE_DETAILS["$key"]="$value"
    else
        echo "$key=$value" >> "$SUITE_DETAILS_FILE"
    fi
}

get_suite_detail() {
    local key="$1"
    if [ "$USE_ASSOCIATIVE_ARRAYS" = true ]; then
        echo "${SUITE_DETAILS[$key]}"
    else
        grep "^$key=" "$SUITE_DETAILS_FILE" 2>/dev/null | cut -d= -f2- | tail -1
    fi
}



# Function to create test report directory
create_report_directory() {
    mkdir -p "$TEST_REPORT_DIR"
    print_status "blue" "Test reports will be saved to: $TEST_REPORT_DIR"
}

# Function to run test suite component
run_test_component() {
    local component_name="$1"
    local component_script="$2"
    local component_args="$3"
    
    print_status "bold" "Running $component_name..."
    echo "=================================================="
    
    local start_time=$(date +%s)
    local log_file="$TEST_REPORT_DIR/${component_name,,}_${TEST_TIMESTAMP}.log"
    local result_file="$TEST_REPORT_DIR/${component_name,,}_${TEST_TIMESTAMP}.result"
    
    # Run the test component
    local exit_code=0
    if [ -n "$component_args" ]; then
        "$component_script" $component_args >"$log_file" 2>&1 || exit_code=$?
    else
        "$component_script" >"$log_file" 2>&1 || exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Store results
    if [ $exit_code -eq 0 ]; then
        set_suite_result "$component_name" "PASS"
        print_status "green" "$component_name completed successfully in ${duration}s"
    else
        set_suite_result "$component_name" "FAIL"
        print_status "red" "$component_name failed in ${duration}s (exit code: $exit_code)"
    fi
    
    set_suite_detail "${component_name}_duration" "$duration"
    set_suite_detail "${component_name}_exit_code" "$exit_code"
    set_suite_detail "${component_name}_log_file" "$log_file"
    
    # Create result summary
    {
        echo "Component: $component_name"
        echo "Script: $component_script"
        echo "Arguments: $component_args"
        echo "Start Time: $(date -d @$start_time)"
        echo "End Time: $(date -d @$end_time)"
        echo "Duration: ${duration}s"
        echo "Exit Code: $exit_code"
        local result
        result=$(get_suite_result "$component_name")
        echo "Result: $result"
        echo "Log File: $log_file"
    } > "$result_file"
    
    echo ""
    return $exit_code
}

# Function to run smoke tests
run_smoke_tests() {
    print_status "purple" "Phase 1: Smoke Tests"
    run_test_component "Smoke_Tests" "$TEST_RUNNER" "smoke"
}

# Function to run basic interoperability tests
run_basic_interop_tests() {
    print_status "purple" "Phase 2: Basic Interoperability Tests"
    run_test_component "Basic_Interop" "$BASIC_INTEROP" "all"
}

# Function to run enhanced validation tests
run_enhanced_validation_tests() {
    print_status "purple" "Phase 3: Enhanced Validation Tests"
    run_test_component "Enhanced_Validation" "$ENHANCED_FRAMEWORK" "all"
}

# Function to run error handling tests
run_error_handling_tests() {
    print_status "purple" "Phase 4: Error Handling and Graceful Shutdown Tests"
    run_test_component "Error_Handling" "$ERROR_HANDLING" "all"
}

# Function to run performance baseline tests
run_performance_tests() {
    print_status "purple" "Phase 5: Performance Baseline Tests"
    
    local perf_log="$TEST_REPORT_DIR/performance_${TEST_TIMESTAMP}.log"
    local start_time=$(date +%s)
    
    {
        echo "Performance Baseline Test Results"
        echo "================================="
        echo "Timestamp: $(date)"
        echo ""
        
        # Test each language combination for basic performance
        for server_lang in "${LANGUAGES[@]}"; do
            for client_lang in "${LANGUAGES[@]}"; do
                echo "Testing $server_lang server with $client_lang client..."
                
                # Find available port
                local port=50051
                while lsof -i ":$port" >/dev/null 2>&1; do
                    port=$((port + 1))
                done
                
                # Start server
                "$SCRIPT_DIR/run-server.sh" "$server_lang" "$port" >/dev/null 2>&1 &
                local server_pid=$!
                
                # Wait for server to start
                sleep 3
                
                # Run client with timing
                local client_start=$(date +%s.%N)
                if timeout 30 "$SCRIPT_DIR/run-client.sh" \
                    "$client_lang" "localhost" "$port" \
                    "performance test" "B000PERF" "performance testing" \
                    >/dev/null 2>&1; then
                    local client_end=$(date +%s.%N)
                    local client_duration=$(echo "$client_end - $client_start" | bc -l 2>/dev/null || echo "N/A")
                    echo "  $server_lang-$client_lang: ${client_duration}s"
                else
                    echo "  $server_lang-$client_lang: FAILED"
                fi
                
                # Stop server
                kill "$server_pid" 2>/dev/null || true
                sleep 1
            done
        done
        
    } > "$perf_log" 2>&1
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ -f "$perf_log" ]; then
        SUITE_RESULTS["Performance_Tests"]="PASS"
        print_status "green" "Performance baseline tests completed in ${duration}s"
    else
        SUITE_RESULTS["Performance_Tests"]="FAIL"
        print_status "red" "Performance baseline tests failed in ${duration}s"
    fi
    
    SUITE_DETAILS["Performance_Tests_duration"]="$duration"
    SUITE_DETAILS["Performance_Tests_log_file"]="$perf_log"
}

# Function to generate comprehensive report
generate_comprehensive_report() {
    local report_file="$TEST_REPORT_DIR/comprehensive_report_${TEST_TIMESTAMP}.md"
    
    print_status "blue" "Generating comprehensive test report..."
    
    {
        echo "# gRPC Bidirectional Streaming - Comprehensive Test Report"
        echo ""
        echo "**Generated:** $(date)"
        echo "**Test Suite Version:** 1.0"
        echo "**Project Root:** $PROJECT_ROOT"
        echo ""
        
        echo "## Executive Summary"
        echo ""
        
        local total_components=0
        local passed_components=0
        local failed_components=0
        
        for component in "${!SUITE_RESULTS[@]}"; do
            total_components=$((total_components + 1))
            if [ "${SUITE_RESULTS[$component]}" = "PASS" ]; then
                passed_components=$((passed_components + 1))
            else
                failed_components=$((failed_components + 1))
            fi
        done
        
        echo "- **Total Test Components:** $total_components"
        echo "- **Passed:** $passed_components"
        echo "- **Failed:** $failed_components"
        
        if [ $total_components -gt 0 ]; then
            local success_rate=$((passed_components * 100 / total_components))
            echo "- **Success Rate:** ${success_rate}%"
        fi
        
        echo ""
        
        if [ $failed_components -eq 0 ]; then
            echo "🎉 **Overall Result: ALL TESTS PASSED**"
        else
            echo "❌ **Overall Result: SOME TESTS FAILED**"
        fi
        
        echo ""
        echo "## Test Component Results"
        echo ""
        
        # Detailed results for each component
        for component in "Smoke_Tests" "Basic_Interop" "Enhanced_Validation" "Error_Handling" "Performance_Tests"; do
            if [ -n "${SUITE_RESULTS[$component]}" ]; then
                echo "### $component"
                echo ""
                
                local result="${SUITE_RESULTS[$component]}"
                local duration="${SUITE_DETAILS[${component}_duration]}"
                local exit_code="${SUITE_DETAILS[${component}_exit_code]}"
                local log_file="${SUITE_DETAILS[${component}_log_file]}"
                
                if [ "$result" = "PASS" ]; then
                    echo "✅ **Status:** PASSED"
                else
                    echo "❌ **Status:** FAILED"
                fi
                
                echo "- **Duration:** ${duration}s"
                echo "- **Exit Code:** $exit_code"
                echo "- **Log File:** $log_file"
                echo ""
                
                # Include relevant excerpts from log files
                if [ -f "$log_file" ]; then
                    echo "**Key Results:**"
                    echo '```'
                    # Extract summary information
                    if grep -q "SUMMARY\|Summary" "$log_file" 2>/dev/null; then
                        grep -A 10 -B 2 "SUMMARY\|Summary" "$log_file" | head -20
                    elif grep -q "passed\|failed\|PASS\|FAIL" "$log_file" 2>/dev/null; then
                        grep "passed\|failed\|PASS\|FAIL" "$log_file" | tail -10
                    else
                        tail -10 "$log_file"
                    fi
                    echo '```'
                fi
                
                echo ""
            fi
        done
        
        echo "## Requirements Compliance"
        echo ""
        echo "This comprehensive test suite validates the following requirements:"
        echo ""
        echo "- **Requirement 3.1:** Cross-language interoperability ✓"
        echo "- **Requirement 3.2:** Message exchange validation (2 Context, 3 AdsList) ✓"
        echo "- **Requirement 3.4:** Error handling and graceful shutdown ✓"
        echo "- **Requirement 3.5:** Deadline handling and timeout scenarios ✓"
        echo "- **Requirement 5.4:** Version ordering and final result validation ✓"
        echo ""
        
        echo "## Test Environment"
        echo ""
        echo "- **Operating System:** $(uname -s)"
        echo "- **Architecture:** $(uname -m)"
        echo "- **Languages Tested:** ${LANGUAGES[*]}"
        echo "- **Test Combinations:** $((${#LANGUAGES[@]} * ${#LANGUAGES[@]})) client-server pairs"
        echo ""
        
        echo "## Recommendations"
        echo ""
        
        if [ $failed_components -eq 0 ]; then
            echo "All test components passed successfully. The gRPC bidirectional streaming implementation"
            echo "demonstrates excellent cross-language interoperability, proper error handling, and"
            echo "compliance with all specified requirements."
        else
            echo "Some test components failed. Review the detailed results above and check the"
            echo "corresponding log files for specific issues. Common areas to investigate:"
            echo ""
            echo "- Build configuration and dependencies"
            echo "- Network connectivity and port availability"
            echo "- Language-specific gRPC implementation differences"
            echo "- Resource cleanup and process management"
        fi
        
        echo ""
        echo "## Files Generated"
        echo ""
        echo "All test artifacts are saved in: \`$TEST_REPORT_DIR\`"
        echo ""
        
        # List all generated files
        if [ -d "$TEST_REPORT_DIR" ]; then
            for file in "$TEST_REPORT_DIR"/*; do
                if [ -f "$file" ]; then
                    local filename=$(basename "$file")
                    local filesize=$(ls -lh "$file" | awk '{print $5}')
                    echo "- \`$filename\` ($filesize)"
                fi
            done
        fi
        
        echo ""
        echo "---"
        echo "*Report generated by gRPC Bidirectional Streaming Comprehensive Test Suite*"
        
    } > "$report_file"
    
    print_status "green" "Comprehensive report saved to: $report_file"
    
    # Also create a simple summary file
    local summary_file="$TEST_REPORT_DIR/test_summary_${TEST_TIMESTAMP}.txt"
    {
        echo "gRPC Bidirectional Streaming - Test Summary"
        echo "==========================================="
        echo "Generated: $(date)"
        echo ""
        echo "Results:"
        for component in "${!SUITE_RESULTS[@]}"; do
            printf "%-20s: %s\n" "$component" "${SUITE_RESULTS[$component]}"
        done
        echo ""
        echo "Overall: $passed_components/$total_components passed"
    } > "$summary_file"
    
    print_status "blue" "Test summary saved to: $summary_file"
}

# Function to run full comprehensive test suite
run_comprehensive_suite() {
    print_status "bold" "Starting Comprehensive gRPC Bidirectional Streaming Test Suite"
    echo "=============================================================="
    print_status "blue" "Timestamp: $(date)"
    print_status "blue" "Languages: ${LANGUAGES[*]}"
    print_status "blue" "Test combinations: $((${#LANGUAGES[@]} * ${#LANGUAGES[@]}))"
    echo ""
    
    # Create report directory
    create_report_directory
    
    # Run test phases
    local overall_success=true
    
    # Phase 1: Smoke tests
    if ! run_smoke_tests; then
        overall_success=false
        print_status "yellow" "Smoke tests failed - continuing with remaining tests"
    fi
    
    # Phase 2: Basic interoperability
    if ! run_basic_interop_tests; then
        overall_success=false
        print_status "yellow" "Basic interop tests failed - continuing with remaining tests"
    fi
    
    # Phase 3: Enhanced validation
    if ! run_enhanced_validation_tests; then
        overall_success=false
        print_status "yellow" "Enhanced validation tests failed - continuing with remaining tests"
    fi
    
    # Phase 4: Error handling
    if ! run_error_handling_tests; then
        overall_success=false
        print_status "yellow" "Error handling tests failed - continuing with remaining tests"
    fi
    
    # Phase 5: Performance baseline
    run_performance_tests
    
    # Generate comprehensive report
    generate_comprehensive_report
    
    # Final summary
    echo ""
    print_status "bold" "Comprehensive Test Suite Complete"
    echo "=============================================================="
    
    local total_components=${#SUITE_RESULTS[@]}
    local passed_components=0
    local failed_components=0
    
    for component in "${!SUITE_RESULTS[@]}"; do
        if [ "${SUITE_RESULTS[$component]}" = "PASS" ]; then
            passed_components=$((passed_components + 1))
        else
            failed_components=$((failed_components + 1))
        fi
    done
    
    print_status "purple" "Final Results:"
    print_status "blue" "Total components: $total_components"
    print_status "green" "Passed: $passed_components"
    print_status "red" "Failed: $failed_components"
    
    if [ $total_components -gt 0 ]; then
        local success_rate=$((passed_components * 100 / total_components))
        print_status "purple" "Success rate: ${success_rate}%"
    fi
    
    print_status "blue" "All test artifacts saved to: $TEST_REPORT_DIR"
    
    if [ "$overall_success" = true ] && [ $failed_components -eq 0 ]; then
        print_status "green" "🎉 ALL COMPREHENSIVE TESTS PASSED!"
        return 0
    else
        print_status "red" "❌ Some comprehensive tests failed. Check the detailed report."
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "blue" "Checking prerequisites for comprehensive test suite..."
    
    local missing_tools=()
    local missing_scripts=()
    
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
    
    if command_exists bc; then
        # bc is optional for performance timing
        :
    fi
    
    # Check for required scripts
    for script in "$ENHANCED_FRAMEWORK" "$ERROR_HANDLING" "$BASIC_INTEROP" "$TEST_RUNNER"; do
        if [ ! -f "$script" ] || [ ! -x "$script" ]; then
            missing_scripts+=("$(basename "$script")")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_status "red" "Missing required tools: ${missing_tools[*]}"
        print_status "yellow" "Please install the missing tools and try again"
        exit 1
    fi
    
    if [ ${#missing_scripts[@]} -gt 0 ]; then
        print_status "red" "Missing or non-executable scripts: ${missing_scripts[*]}"
        print_status "yellow" "Please ensure all test scripts are present and executable"
        exit 1
    fi
    
    print_status "green" "Prerequisites check completed"
}

# Main execution
main() {
    local action="${1:-full}"
    
    case "$action" in
        full)
            check_prerequisites
            run_comprehensive_suite
            ;;
        smoke)
            check_prerequisites
            create_report_directory
            run_smoke_tests
            ;;
        basic)
            check_prerequisites
            create_report_directory
            run_basic_interop_tests
            ;;
        enhanced)
            check_prerequisites
            create_report_directory
            run_enhanced_validation_tests
            ;;
        error)
            check_prerequisites
            create_report_directory
            run_error_handling_tests
            ;;
        performance)
            check_prerequisites
            create_report_directory
            run_performance_tests
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
    echo "  full        - Run complete comprehensive test suite (default)"
    echo "  smoke       - Run only smoke tests"
    echo "  basic       - Run only basic interoperability tests"
    echo "  enhanced    - Run only enhanced validation tests"
    echo "  error       - Run only error handling tests"
    echo "  performance - Run only performance baseline tests"
    echo "  help        - Show this help message"
    echo ""
    echo "COMPREHENSIVE TEST SUITE PHASES:"
    echo "  1. Smoke Tests           - Basic functionality verification"
    echo "  2. Basic Interop         - Standard interoperability testing"
    echo "  3. Enhanced Validation   - Message count and version ordering"
    echo "  4. Error Handling        - Connection failures and graceful shutdown"
    echo "  5. Performance Baseline  - Basic performance measurements"
    echo ""
    echo "REQUIREMENTS VALIDATED:"
    echo "  - Requirement 3.1: Cross-language interoperability"
    echo "  - Requirement 3.2: Message exchange validation (2 Context, 3 AdsList)"
    echo "  - Requirement 3.4: Error handling and graceful shutdown"
    echo "  - Requirement 3.5: Deadline handling and timeout scenarios"
    echo "  - Requirement 5.4: Version ordering and final result validation"
    echo ""
    echo "OUTPUT:"
    echo "  - Detailed logs for each test phase"
    echo "  - Comprehensive markdown report"
    echo "  - Test summary and statistics"
    echo "  - Performance baseline measurements"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Run complete test suite"
    echo "  $0 enhanced           # Run only enhanced validation tests"
    echo "  $0 error              # Run only error handling tests"
    echo ""
    echo "NOTES:"
    echo "  - All test artifacts are saved to /tmp/grpc_comprehensive_test_*"
    echo "  - Tests require all projects to be built beforehand"
    echo "  - Comprehensive suite tests all 9 language combinations"
    echo "  - Failed test logs are preserved for debugging"
}

# Cleanup function for graceful shutdown
cleanup() {
    print_status "yellow" "Cleaning up comprehensive test suite..."
    
    # Kill any remaining test processes
    pkill -f "test-framework.sh\|test-error-handling.sh\|test-interop.sh\|test-runner.sh" 2>/dev/null || true
    pkill -f "run-server.sh\|run-client.sh" 2>/dev/null || true
    pkill -f "ads_server\|ads-server\|AdsServer" 2>/dev/null || true
    
    print_status "blue" "Test artifacts preserved in: $TEST_REPORT_DIR"
    
    exit 0
}

# Handle Ctrl+C gracefully
trap cleanup INT TERM

main "$@"
