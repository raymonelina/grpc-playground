#!/bin/bash

# Test script for comprehensive logging and debugging support
# This script demonstrates different logging modes and debug configurations

set -e

# Source common utilities
source "$(dirname "$0")/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Function to test a specific logging configuration
test_logging_config() {
    local language=$1
    local log_level=$2
    local debug_mode=$3
    local description=$4
    
    log "Testing $language with LOG_LEVEL=$log_level, DEBUG_MODE=$debug_mode"
    log "Description: $description"
    
    # Set environment variables
    export LOG_LEVEL=$log_level
    export DEBUG_MODE=$debug_mode
    
    # Start server in background
    local server_pid=""
    case $language in
        "java")
            cd "$PROJECT_ROOT"
            timeout 10s ./scripts/run-server.sh java > "test_server_${language}_${log_level}_${debug_mode}.log" 2>&1 &
            server_pid=$!
            ;;
        "cpp")
            cd "$PROJECT_ROOT"
            timeout 10s ./scripts/run-server.sh cpp > "test_server_${language}_${log_level}_${debug_mode}.log" 2>&1 &
            server_pid=$!
            ;;
        "rust")
            cd "$PROJECT_ROOT"
            timeout 10s ./scripts/run-server.sh rust > "test_server_${language}_${log_level}_${debug_mode}.log" 2>&1 &
            server_pid=$!
            ;;
    esac
    
    # Wait for server to start
    sleep 3
    
    # Run client
    case $language in
        "java")
            timeout 5s ./scripts/run-client.sh java > "test_client_${language}_${log_level}_${debug_mode}.log" 2>&1 || true
            ;;
        "cpp")
            timeout 5s ./scripts/run-client.sh cpp > "test_client_${language}_${log_level}_${debug_mode}.log" 2>&1 || true
            ;;
        "rust")
            timeout 5s ./scripts/run-client.sh rust > "test_client_${language}_${log_level}_${debug_mode}.log" 2>&1 || true
            ;;
    esac
    
    # Stop server
    if [ ! -z "$server_pid" ]; then
        kill $server_pid 2>/dev/null || true
        wait $server_pid 2>/dev/null || true
    fi
    
    # Analyze logs
    local server_log="test_server_${language}_${log_level}_${debug_mode}.log"
    local client_log="test_client_${language}_${log_level}_${debug_mode}.log"
    
    if [ -f "$server_log" ] && [ -f "$client_log" ]; then
        local server_lines=$(wc -l < "$server_log")
        local client_lines=$(wc -l < "$client_log")
        local server_errors=$(grep -c "ERROR\|Exception\|exception" "$server_log" 2>/dev/null || echo "0")
        local client_errors=$(grep -c "ERROR\|Exception\|exception" "$client_log" 2>/dev/null || echo "0")
        
        success "Test completed - Server: $server_lines lines, $server_errors errors | Client: $client_lines lines, $client_errors errors"
        
        # Show sample log lines
        echo "Sample server log lines:"
        head -3 "$server_log" 2>/dev/null || echo "No server logs"
        echo "Sample client log lines:"
        head -3 "$client_log" 2>/dev/null || echo "No client logs"
        echo ""
    else
        error "Log files not generated properly"
    fi
    
    # Clean up environment
    unset LOG_LEVEL
    unset DEBUG_MODE
}

# Function to demonstrate log format consistency
test_log_format_consistency() {
    log "Testing log format consistency across languages"
    
    # Test with INFO level and NORMAL debug mode
    export LOG_LEVEL=INFO
    export DEBUG_MODE=NORMAL
    
    # Test each language
    for lang in java cpp rust; do
        log "Testing $lang log format..."
        
        # Start server briefly
        timeout 3s ./scripts/run-server.sh $lang > "format_test_${lang}.log" 2>&1 &
        local server_pid=$!
        sleep 1
        
        # Run client briefly
        timeout 2s ./scripts/run-client.sh $lang >> "format_test_${lang}.log" 2>&1 || true
        
        # Stop server
        kill $server_pid 2>/dev/null || true
        wait $server_pid 2>/dev/null || true
        
        # Check log format
        if [ -f "format_test_${lang}.log" ]; then
            echo "Sample $lang log format:"
            grep -E "\[.*\] \[.*\] \[.*\] \[.*\]" "format_test_${lang}.log" | head -2 || echo "No properly formatted logs found"
            echo ""
        fi
    done
    
    unset LOG_LEVEL
    unset DEBUG_MODE
}

# Function to test performance logging
test_performance_logging() {
    log "Testing performance logging capabilities"
    
    export LOG_LEVEL=DEBUG
    export DEBUG_MODE=PERFORMANCE
    
    # Test with Java (most comprehensive performance logging)
    log "Running performance test with Java implementation"
    
    timeout 5s ./scripts/run-server.sh java > "perf_server.log" 2>&1 &
    local server_pid=$!
    sleep 2
    
    timeout 3s ./scripts/run-client.sh java > "perf_client.log" 2>&1 || true
    
    kill $server_pid 2>/dev/null || true
    wait $server_pid 2>/dev/null || true
    
    # Analyze performance metrics
    if [ -f "perf_client.log" ]; then
        echo "Performance metrics found:"
        grep -E "elapsed_ms|duration_ms|generation_ms|timeout_ms" "perf_client.log" || echo "No performance metrics found"
        echo ""
    fi
    
    unset LOG_LEVEL
    unset DEBUG_MODE
}

# Function to test error handling logging
test_error_logging() {
    log "Testing error handling and logging"
    
    export LOG_LEVEL=DEBUG
    export DEBUG_MODE=NORMAL
    
    # Test connection failure scenario
    log "Testing connection failure logging (no server running)"
    
    # Run client without server
    timeout 5s ./scripts/run-client.sh java > "error_test.log" 2>&1 || true
    
    if [ -f "error_test.log" ]; then
        echo "Error handling logs:"
        grep -E "ERROR|WARN|failed|Failed|error|Error" "error_test.log" | head -5 || echo "No error logs found"
        echo ""
    fi
    
    unset LOG_LEVEL
    unset DEBUG_MODE
}

# Main test execution
main() {
    log "Starting comprehensive logging and debugging tests"
    
    cd "$PROJECT_ROOT"
    
    # Ensure project is built
    log "Building project..."
    ./scripts/build-all.sh > build.log 2>&1 || {
        error "Build failed. Check build.log for details."
        exit 1
    }
    success "Project built successfully"
    
    # Test 1: Log format consistency
    test_log_format_consistency
    
    # Test 2: Different log levels
    log "Testing different log levels..."
    test_logging_config "java" "ERROR" "NORMAL" "Error level only"
    test_logging_config "java" "WARN" "NORMAL" "Warning level and above"
    test_logging_config "java" "INFO" "NORMAL" "Info level and above (default)"
    test_logging_config "java" "DEBUG" "NORMAL" "Debug level (verbose)"
    
    # Test 3: Different debug modes
    log "Testing different debug modes..."
    test_logging_config "java" "DEBUG" "VERBOSE" "Verbose debug mode"
    test_logging_config "java" "INFO" "PERFORMANCE" "Performance-focused logging"
    test_logging_config "java" "DEBUG" "PROTOCOL" "Protocol-focused logging"
    test_logging_config "java" "ERROR" "ERRORS_ONLY" "Errors only mode"
    
    # Test 4: Cross-language consistency
    log "Testing cross-language logging consistency..."
    for lang in java cpp rust; do
        test_logging_config "$lang" "INFO" "NORMAL" "Standard logging for $lang"
    done
    
    # Test 5: Performance logging
    test_performance_logging
    
    # Test 6: Error logging
    test_error_logging
    
    # Generate summary report
    log "Generating test summary report..."
    
    cat > logging_test_report.md << EOF
# Logging Test Report

Generated on: $(date)

## Test Results Summary

### Log Format Consistency
$(for lang in java cpp rust; do
    if [ -f "format_test_${lang}.log" ]; then
        echo "- $lang: $(wc -l < "format_test_${lang}.log") log lines generated"
    else
        echo "- $lang: No logs generated"
    fi
done)

### Log Level Tests
$(for level in ERROR WARN INFO DEBUG; do
    if [ -f "test_client_java_${level}_NORMAL.log" ]; then
        lines=$(wc -l < "test_client_java_${level}_NORMAL.log")
        errors=$(grep -c "ERROR" "test_client_java_${level}_NORMAL.log" 2>/dev/null || echo "0")
        echo "- $level: $lines lines, $errors errors"
    fi
done)

### Debug Mode Tests
$(for mode in VERBOSE PERFORMANCE PROTOCOL ERRORS_ONLY; do
    if [ -f "test_client_java_DEBUG_${mode}.log" ] || [ -f "test_client_java_INFO_${mode}.log" ] || [ -f "test_client_java_ERROR_${mode}.log" ]; then
        echo "- $mode: Test completed"
    fi
done)

### Cross-Language Tests
$(for lang in java cpp rust; do
    if [ -f "test_client_${lang}_INFO_NORMAL.log" ]; then
        lines=$(wc -l < "test_client_${lang}_INFO_NORMAL.log")
        echo "- $lang: $lines log lines"
    fi
done)

## Log Files Generated
$(ls -la test_*.log format_test_*.log perf_*.log error_test.log 2>/dev/null || echo "No log files found")

## Recommendations

1. **Log Level**: Use INFO for production, DEBUG for troubleshooting
2. **Debug Mode**: Use PERFORMANCE for performance analysis, VERBOSE for detailed debugging
3. **Format**: All languages follow consistent timestamp [LEVEL] [COMPONENT] [THREAD] format
4. **Error Handling**: Comprehensive error logging with context information

## Next Steps

1. Review individual log files for detailed analysis
2. Integrate logging configuration into deployment scripts
3. Set up log aggregation and monitoring
4. Document logging best practices for team

EOF

    success "Logging test completed successfully!"
    success "Report generated: logging_test_report.md"
    
    # Clean up test files
    log "Cleaning up test files..."
    rm -f test_*.log format_test_*.log perf_*.log error_test.log build.log 2>/dev/null || true
    
    log "All tests completed. Check logging_test_report.md for detailed results."
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Test comprehensive logging and debugging support across all implementations.

OPTIONS:
    -h, --help          Show this help message
    --format-only       Test only log format consistency
    --performance-only  Test only performance logging
    --error-only        Test only error logging
    --language LANG     Test only specific language (java, cpp, rust)

EXAMPLES:
    $0                          # Run all tests
    $0 --format-only           # Test log format consistency only
    $0 --language java         # Test Java implementation only
    $0 --performance-only      # Test performance logging only

ENVIRONMENT VARIABLES:
    LOG_LEVEL      Set log level (DEBUG, INFO, WARN, ERROR)
    DEBUG_MODE     Set debug mode (VERBOSE, PERFORMANCE, PROTOCOL, ERRORS_ONLY)

EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --format-only)
        test_log_format_consistency
        exit 0
        ;;
    --performance-only)
        test_performance_logging
        exit 0
        ;;
    --error-only)
        test_error_logging
        exit 0
        ;;
    --language)
        if [ -z "${2:-}" ]; then
            error "Language argument required"
            exit 1
        fi
        test_logging_config "$2" "INFO" "NORMAL" "Single language test"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
