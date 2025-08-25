#!/bin/bash

# Script to run gRPC clients for different languages
# Supports Java, C++, and Rust clients

set -e

# Source common utilities
source "$(dirname "$0")/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
DEFAULT_HOST="localhost"
DEFAULT_PORT=50051
DEFAULT_LANGUAGE="java"
DEFAULT_QUERY="coffee maker"
DEFAULT_ASIN="B000123456"
DEFAULT_UNDERSTANDING="premium coffee brewing equipment"



# Function to check if server is running
is_server_running() {
    local host="$1"
    local port="$2"
    
    # Try to connect to the server
    if command_exists nc; then
        nc -z "$host" "$port" 2>/dev/null
    elif command_exists telnet; then
        timeout 2 telnet "$host" "$port" </dev/null >/dev/null 2>&1
    else
        # Fallback: assume server is running
        print_status "yellow" "Cannot verify server status (nc/telnet not available)"
        return 0
    fi
}

# Function to run Java client
run_java_client() {
    local host="$1"
    local port="$2"
    local query="$3"
    local asin="$4"
    local understanding="$5"
    
    print_status "blue" "Running Java client..."
    
    cd "$PROJECT_ROOT/java"
    
    if [ ! -f "pom.xml" ]; then
        print_status "red" "Java project not found. Please build the project first."
        exit 1
    fi
    
    if ! command_exists mvn; then
        print_status "red" "Maven not found. Please install Maven."
        exit 1
    fi
    
    # Check if client class exists
    if [ ! -f "src/main/java/com/example/ads/client/AdsClient.java" ]; then
        print_status "red" "Java client implementation not found."
        exit 1
    fi
    
    # Run the client
    print_status "green" "Java client connecting to $host:$port..."
    mvn exec:java -Dexec.mainClass="com.example.ads.client.AdsClient" \
        -Dexec.args="$host $port \"$query\" \"$asin\" \"$understanding\"" -q
}

# Function to run C++ client
run_cpp_client() {
    local host="$1"
    local port="$2"
    local query="$3"
    local asin="$4"
    local understanding="$5"
    
    print_status "blue" "Running C++ client..."
    
    cd "$PROJECT_ROOT/cpp"
    
    local client_binary="build/client/ads_client"
    
    if [ ! -f "$client_binary" ]; then
        print_status "red" "C++ client binary not found at $client_binary. Please build the project first."
        exit 1
    fi
    
    # Run the client
    print_status "green" "C++ client connecting to $host:$port..."
    "$client_binary" "$host" "$port" "$query" "$asin" "$understanding"
}

# Function to run Rust client
run_rust_client() {
    local host="$1"
    local port="$2"
    local query="$3"
    local asin="$4"
    local understanding="$5"
    
    print_status "blue" "Running Rust client..."
    
    cd "$PROJECT_ROOT/rust"
    
    if [ ! -f "Cargo.toml" ]; then
        print_status "red" "Rust workspace not found. Please build the project first."
        exit 1
    fi
    
    if ! command_exists cargo; then
        print_status "red" "Cargo not found. Please install Rust and Cargo."
        exit 1
    fi
    
    # Run the client
    print_status "green" "Rust client connecting to $host:$port..."
    cargo run --bin ads-client -- "$host" "$port" "$query" "$asin" "$understanding"
}

# Function to run client with language detection
run_client() {
    local language="$1"
    local host="$2"
    local port="$3"
    local query="$4"
    local asin="$5"
    local understanding="$6"
    
    # Check if server is running
    if ! is_server_running "$host" "$port"; then
        print_status "red" "Cannot connect to server at $host:$port. Please make sure the server is running."
        exit 1
    fi
    
    case "$language" in
        java)
            run_java_client "$host" "$port" "$query" "$asin" "$understanding"
            ;;
        cpp|c++)
            run_cpp_client "$host" "$port" "$query" "$asin" "$understanding"
            ;;
        rust)
            run_rust_client "$host" "$port" "$query" "$asin" "$understanding"
            ;;
        *)
            print_status "red" "Unknown language: $language"
            print_usage
            exit 1
            ;;
    esac
}

# Main execution
main() {
    local language="${1:-$DEFAULT_LANGUAGE}"
    local host="${2:-$DEFAULT_HOST}"
    local port="${3:-$DEFAULT_PORT}"
    local query="${4:-$DEFAULT_QUERY}"
    local asin="${5:-$DEFAULT_ASIN}"
    local understanding="${6:-$DEFAULT_UNDERSTANDING}"
    
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - Client Runner"
    echo "=================================================="
    print_status "blue" "Language: $language"
    print_status "blue" "Server: $host:$port"
    print_status "blue" "Query: $query"
    print_status "blue" "ASIN: $asin"
    print_status "blue" "Understanding: $understanding"
    print_status "blue" "Project root: $PROJECT_ROOT"
    
    # Show logging configuration
    local log_level="${LOG_LEVEL:-INFO}"
    local debug_mode="${DEBUG_MODE:-NORMAL}"
    print_status "blue" "Log level: $log_level"
    print_status "blue" "Debug mode: $debug_mode"
    echo ""
    
    case "$language" in
        help|--help|-h)
            print_usage
            ;;
        *)
            # Validate port number
            if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
                print_status "red" "Invalid port number: $port. Please use a port between 1024 and 65535."
                exit 1
            fi
            
            run_client "$language" "$host" "$port" "$query" "$asin" "$understanding"
            ;;
    esac
}

# Print usage information
print_usage() {
    echo "Usage: $0 [LANGUAGE] [HOST] [PORT] [QUERY] [ASIN] [UNDERSTANDING]"
    echo ""
    echo "LANGUAGES:"
    echo "  java        - Run Java client (default)"
    echo "  cpp         - Run C++ client"
    echo "  rust        - Run Rust client"
    echo ""
    echo "PARAMETERS:"
    echo "  HOST        - Server hostname (default: $DEFAULT_HOST)"
    echo "  PORT        - Server port (default: $DEFAULT_PORT)"
    echo "  QUERY       - Search query (default: \"$DEFAULT_QUERY\")"
    echo "  ASIN        - Product ASIN (default: \"$DEFAULT_ASIN\")"
    echo "  UNDERSTANDING - Query understanding (default: \"$DEFAULT_UNDERSTANDING\")"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                                    # Run Java client with defaults"
    echo "  $0 rust                               # Run Rust client with defaults"
    echo "  $0 cpp localhost 8080                 # Run C++ client on port 8080"
    echo "  $0 java localhost 50051 \"laptop\" \"B001\" \"gaming laptop\""
    echo ""
    echo "NOTES:"
    echo "  - Make sure to build the project first using build scripts"
    echo "  - The server must be running before starting the client"
    echo "  - Use quotes around parameters that contain spaces"
}

main "$@"
