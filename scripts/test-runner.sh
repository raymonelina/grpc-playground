#!/bin/bash

# Test runner for gRPC bidirectional streaming project
# Provides various testing utilities and verification scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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
        *) echo "$message" ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to test protobuf generation
test_proto_generation() {
    print_status "blue" "Testing protobuf code generation..."
    
    # Clean and regenerate
    if "$SCRIPT_DIR/generate-proto.sh" regenerate all >/dev/null 2>&1; then
        print_status "green" "Protobuf generation test passed"
        return 0
    else
        print_status "red" "Protobuf generation test failed"
        return 1
    fi
}

# Function to test builds
test_builds() {
    local language="${1:-all}"
    
    print_status "blue" "Testing build process for $language..."
    
    case "$language" in
        java)
            if "$SCRIPT_DIR/build-java.sh" rebuild >/dev/null 2>&1; then
                print_status "green" "Java build test passed"
                return 0
            else
                print_status "red" "Java build test failed"
                return 1
            fi
            ;;
        cpp)
            if "$SCRIPT_DIR/build-cpp.sh" rebuild >/dev/null 2>&1; then
                print_status "green" "C++ build test passed"
                return 0
            else
                print_status "red" "C++ build test failed"
                return 1
            fi
            ;;
        rust)
            if "$SCRIPT_DIR/build-rust.sh" rebuild >/dev/null 2>&1; then
                print_status "green" "Rust build test passed"
                return 0
            else
                print_status "red" "Rust build test failed"
                return 1
            fi
            ;;
        all)
            local success=true
            test_builds java || success=false
            test_builds cpp || success=false
            test_builds rust || success=false
            
            if [ "$success" = true ]; then
                print_status "green" "All build tests passed"
                return 0
            else
                print_status "red" "Some build tests failed"
                return 1
            fi
            ;;
        *)
            print_status "red" "Unknown language: $language"
            return 1
            ;;
    esac
}

# Function to test server startup
test_server_startup() {
    local language="$1"
    local port="${2:-50051}"
    
    print_status "blue" "Testing $language server startup..."
    
    # Find available port
    while lsof -i ":$port" >/dev/null 2>&1; do
        port=$((port + 1))
    done
    
    # Start server in background
    "$SCRIPT_DIR/run-server.sh" "$language" "$port" >/dev/null 2>&1 &
    local server_pid=$!
    
    # Wait for server to start
    local count=0
    local max_wait=10
    
    while [ $count -lt $max_wait ]; do
        if command_exists nc && nc -z localhost "$port" 2>/dev/null; then
            print_status "green" "$language server startup test passed"
            kill "$server_pid" 2>/dev/null || true
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    print_status "red" "$language server startup test failed"
    kill "$server_pid" 2>/dev/null || true
    return 1
}

# Function to test client connection
test_client_connection() {
    local client_lang="$1"
    local server_lang="$2"
    local port="${3:-50051}"
    
    print_status "blue" "Testing $client_lang client with $server_lang server..."
    
    # Find available port
    while lsof -i ":$port" >/dev/null 2>&1; do
        port=$((port + 1))
    done
    
    # Start server in background
    "$SCRIPT_DIR/run-server.sh" "$server_lang" "$port" >/dev/null 2>&1 &
    local server_pid=$!
    
    # Wait for server to start
    sleep 3
    
    # Test client connection
    if timeout 15 "$SCRIPT_DIR/run-client.sh" "$client_lang" localhost "$port" \
        "test query" "B000TEST" "test understanding" >/dev/null 2>&1; then
        print_status "green" "$client_lang-$server_lang connection test passed"
        kill "$server_pid" 2>/dev/null || true
        return 0
    else
        print_status "red" "$client_lang-$server_lang connection test failed"
        kill "$server_pid" 2>/dev/null || true
        return 1
    fi
}

# Function to run smoke tests
run_smoke_tests() {
    print_status "blue" "Running smoke tests..."
    
    local tests_passed=0
    local tests_total=0
    
    # Test protobuf generation
    tests_total=$((tests_total + 1))
    if test_proto_generation; then
        tests_passed=$((tests_passed + 1))
    fi
    
    # Test builds
    for lang in java cpp rust; do
        tests_total=$((tests_total + 1))
        if test_builds "$lang"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    # Test server startups
    for lang in java cpp rust; do
        tests_total=$((tests_total + 1))
        if test_server_startup "$lang"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    echo ""
    print_status "blue" "Smoke test results: $tests_passed/$tests_total passed"
    
    if [ "$tests_passed" -eq "$tests_total" ]; then
        print_status "green" "All smoke tests passed!"
        return 0
    else
        print_status "red" "Some smoke tests failed"
        return 1
    fi
}

# Function to run quick interop test
run_quick_interop() {
    print_status "blue" "Running quick interoperability test..."
    
    # Test one combination from each language
    local combinations=("java java" "cpp cpp" "rust rust")
    local tests_passed=0
    local tests_total=${#combinations[@]}
    
    for combo in "${combinations[@]}"; do
        read -r server_lang client_lang <<< "$combo"
        if test_client_connection "$client_lang" "$server_lang"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    echo ""
    print_status "blue" "Quick interop results: $tests_passed/$tests_total passed"
    
    if [ "$tests_passed" -eq "$tests_total" ]; then
        print_status "green" "Quick interoperability test passed!"
        return 0
    else
        print_status "red" "Quick interoperability test failed"
        return 1
    fi
}

# Function to verify project structure
verify_structure() {
    print_status "blue" "Verifying project structure..."
    
    local missing_files=()
    
    # Check essential files
    local essential_files=(
        "proto/ads.proto"
        "scripts/generate-proto.sh"
        "scripts/build-all.sh"
        "scripts/run-server.sh"
        "scripts/run-client.sh"
        "scripts/test-interop.sh"
    )
    
    for file in "${essential_files[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    # Check language directories
    local lang_dirs=("java" "cpp" "rust")
    for dir in "${lang_dirs[@]}"; do
        if [ ! -d "$PROJECT_ROOT/$dir" ]; then
            missing_files+=("$dir/")
        fi
    done
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        print_status "green" "Project structure verification passed"
        return 0
    else
        print_status "red" "Missing files/directories: ${missing_files[*]}"
        return 1
    fi
}

# Main execution
main() {
    local action="${1:-smoke}"
    
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - Test Runner"
    echo "=================================================="
    print_status "blue" "Project root: $PROJECT_ROOT"
    echo ""
    
    case "$action" in
        smoke)
            run_smoke_tests
            ;;
        quick-interop)
            run_quick_interop
            ;;
        full-interop)
            "$SCRIPT_DIR/test-interop.sh" all
            ;;
        proto)
            test_proto_generation
            ;;
        build)
            local language="${2:-all}"
            test_builds "$language"
            ;;
        server)
            local language="${2:-java}"
            test_server_startup "$language"
            ;;
        client)
            local client_lang="${2:-java}"
            local server_lang="${3:-java}"
            test_client_connection "$client_lang" "$server_lang"
            ;;
        structure)
            verify_structure
            ;;
        all)
            print_status "blue" "Running comprehensive test suite..."
            echo ""
            
            local all_passed=true
            
            verify_structure || all_passed=false
            echo ""
            
            run_smoke_tests || all_passed=false
            echo ""
            
            run_quick_interop || all_passed=false
            echo ""
            
            if [ "$all_passed" = true ]; then
                print_status "green" "🎉 All tests passed!"
                return 0
            else
                print_status "red" "❌ Some tests failed"
                return 1
            fi
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
    echo "Usage: $0 [ACTION] [OPTIONS...]"
    echo ""
    echo "ACTIONS:"
    echo "  smoke           - Run smoke tests (default)"
    echo "  quick-interop   - Run quick interoperability test"
    echo "  full-interop    - Run full interoperability test suite"
    echo "  proto           - Test protobuf code generation"
    echo "  build [LANG]    - Test build process (java|cpp|rust|all)"
    echo "  server [LANG]   - Test server startup (java|cpp|rust)"
    echo "  client [C] [S]  - Test client-server connection"
    echo "  structure       - Verify project structure"
    echo "  all             - Run comprehensive test suite"
    echo "  help            - Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                      # Run smoke tests"
    echo "  $0 build java           # Test Java build"
    echo "  $0 server rust          # Test Rust server startup"
    echo "  $0 client java cpp      # Test Java client with C++ server"
    echo "  $0 all                  # Run all tests"
    echo ""
    echo "NOTES:"
    echo "  - Smoke tests verify basic functionality"
    echo "  - Quick interop tests same-language combinations"
    echo "  - Full interop tests all 9 language combinations"
    echo "  - Use 'all' for comprehensive testing before releases"
}

# Cleanup function
cleanup() {
    print_status "yellow" "Cleaning up test processes..."
    pkill -f "run-server.sh\|run-client.sh" 2>/dev/null || true
    exit 0
}

# Handle Ctrl+C gracefully
trap cleanup INT TERM

main "$@"