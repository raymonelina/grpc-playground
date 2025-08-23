#!/bin/bash

# Script to run gRPC servers for different languages
# Supports Java, C++, and Rust servers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
DEFAULT_PORT=50051
DEFAULT_LANGUAGE="java"

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    case "$color" in
        "green") echo -e "\033[32m✅ $message\033[0m" ;;
        "red") echo -e "\033[31m❌ $message\033[0m" ;;
        "yellow") echo -e "\033[33m⚠️  $message\033[0m" ;;
        "blue") echo -e "\033[34mℹ️  $message\033[0m" ;;
        *) echo "$message" ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if port is available
is_port_available() {
    local port="$1"
    ! lsof -i ":$port" >/dev/null 2>&1
}

# Function to run Java server
run_java_server() {
    local port="$1"
    
    print_status "blue" "Starting Java server on port $port..."
    
    cd "$PROJECT_ROOT/java"
    
    if [ ! -f "pom.xml" ]; then
        print_status "red" "Java project not found. Please build the project first."
        exit 1
    fi
    
    if ! command_exists mvn; then
        print_status "red" "Maven not found. Please install Maven."
        exit 1
    fi
    
    # Check if server class exists
    if [ ! -f "src/main/java/com/example/ads/server/AdsServer.java" ]; then
        print_status "red" "Java server implementation not found."
        exit 1
    fi
    
    # Run the server
    print_status "green" "Java server starting..."
    mvn exec:java -Dexec.mainClass="com.example.ads.server.AdsServer" -Dexec.args="$port" -q
}

# Function to run C++ server
run_cpp_server() {
    local port="$1"
    
    print_status "blue" "Starting C++ server on port $port..."
    
    cd "$PROJECT_ROOT/cpp"
    
    local server_binary="build/server/ads_server"
    
    if [ ! -f "$server_binary" ]; then
        print_status "red" "C++ server binary not found at $server_binary. Please build the project first."
        exit 1
    fi
    
    # Run the server
    print_status "green" "C++ server starting..."
    "$server_binary" "$port"
}

# Function to run Rust server
run_rust_server() {
    local port="$1"
    
    print_status "blue" "Starting Rust server on port $port..."
    
    cd "$PROJECT_ROOT/rust"
    
    if [ ! -f "Cargo.toml" ]; then
        print_status "red" "Rust workspace not found. Please build the project first."
        exit 1
    fi
    
    if ! command_exists cargo; then
        print_status "red" "Cargo not found. Please install Rust and Cargo."
        exit 1
    fi
    
    # Run the server
    print_status "green" "Rust server starting..."
    cargo run --bin ads-server -- "$port"
}

# Function to run server with language detection
run_server() {
    local language="$1"
    local port="$2"
    
    # Check if port is available
    if ! is_port_available "$port"; then
        print_status "red" "Port $port is already in use. Please choose a different port or stop the existing service."
        exit 1
    fi
    
    case "$language" in
        java)
            run_java_server "$port"
            ;;
        cpp|c++)
            run_cpp_server "$port"
            ;;
        rust)
            run_rust_server "$port"
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
    local port="${2:-$DEFAULT_PORT}"
    
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - Server Runner"
    echo "=================================================="
    print_status "blue" "Language: $language"
    print_status "blue" "Port: $port"
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
            
            run_server "$language" "$port"
            ;;
    esac
}

# Print usage information
print_usage() {
    echo "Usage: $0 [LANGUAGE] [PORT]"
    echo ""
    echo "LANGUAGES:"
    echo "  java        - Run Java server (default)"
    echo "  cpp         - Run C++ server"
    echo "  rust        - Run Rust server"
    echo ""
    echo "PORT:"
    echo "  Port number to bind the server (default: $DEFAULT_PORT)"
    echo "  Must be between 1024 and 65535"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Run Java server on port $DEFAULT_PORT"
    echo "  $0 rust               # Run Rust server on port $DEFAULT_PORT"
    echo "  $0 cpp 8080           # Run C++ server on port 8080"
    echo ""
    echo "NOTES:"
    echo "  - Make sure to build the project first using build scripts"
    echo "  - The server will run until interrupted (Ctrl+C)"
    echo "  - Only one server can run on a port at a time"
}

# Handle Ctrl+C gracefully
trap 'print_status "yellow" "Server shutting down..."; exit 0' INT TERM

main "$@"