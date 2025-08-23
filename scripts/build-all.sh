#!/bin/bash

# Master build script for all languages
# Supports build, clean, and rebuild operations for all languages

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
        *) echo "$message" ;;
    esac
}

# Function to run a script and handle errors
run_script() {
    local script_name="$1"
    local action="${2:-build}"
    local script_path="$SCRIPT_DIR/$script_name"
    
    echo ""
    print_status "blue" "Running $script_name $action..."
    echo "----------------------------------------"
    
    if [ -f "$script_path" ] && [ -x "$script_path" ]; then
        if "$script_path" "$action"; then
            print_status "green" "$script_name $action completed successfully"
        else
            print_status "red" "$script_name $action failed"
            return 1
        fi
    else
        print_status "red" "$script_name not found or not executable"
        return 1
    fi
}

# Function to clean all projects
clean_all() {
    print_status "blue" "Cleaning all projects..."
    
    # Clean using individual scripts
    run_script "generate-proto.sh" "clean" || true
    run_script "build-java.sh" "clean" || true
    run_script "build-cpp.sh" "clean" || true
    run_script "build-rust.sh" "clean" || true
    
    # Additional manual cleanup
    rm -rf "$PROJECT_ROOT/java/generated" "$PROJECT_ROOT/cpp/generated" "$PROJECT_ROOT/rust/generated" 2>/dev/null || true
    rm -rf "$PROJECT_ROOT/java/target" "$PROJECT_ROOT/cpp/build" "$PROJECT_ROOT/rust/target" 2>/dev/null || true
    
    print_status "green" "All projects cleaned"
}

# Function to build all projects
build_all() {
    print_status "blue" "Building all projects..."
    
    # Generate protobuf code first
    run_script "generate-proto.sh" "generate"
    
    # Build each language
    run_script "build-java.sh" "build"
    run_script "build-cpp.sh" "build"
    run_script "build-rust.sh" "build"
    
    print_status "green" "All projects built successfully"
}

# Function to build specific language
build_language() {
    local language="$1"
    local action="${2:-build}"
    
    case "$language" in
        java)
            if [ "$action" = "build" ]; then
                run_script "generate-proto.sh" "generate" "java"
            fi
            run_script "build-java.sh" "$action"
            ;;
        cpp)
            if [ "$action" = "build" ]; then
                run_script "generate-proto.sh" "generate" "cpp"
            fi
            run_script "build-cpp.sh" "$action"
            ;;
        rust)
            if [ "$action" = "build" ]; then
                run_script "generate-proto.sh" "generate" "rust"
            fi
            run_script "build-rust.sh" "$action"
            ;;
        *)
            print_status "red" "Unknown language: $language"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    local target="${1:-all}"
    local action="${2:-build}"
    
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - Master Build Script"
    echo "=================================================="
    print_status "blue" "Project root: $PROJECT_ROOT"
    echo ""
    
    case "$target" in
        proto)
            run_script "generate-proto.sh" "$action"
            ;;
        java|cpp|rust)
            build_language "$target" "$action"
            ;;
        all)
            case "$action" in
                build)
                    build_all
                    ;;
                clean)
                    clean_all
                    ;;
                rebuild)
                    print_status "blue" "Rebuilding all projects (clean + build)..."
                    clean_all
                    echo ""
                    build_all
                    ;;
                *)
                    print_status "red" "Unknown action: $action"
                    print_usage
                    exit 1
                    ;;
            esac
            ;;
        clean)
            # Backward compatibility
            clean_all
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            print_status "red" "Unknown target: $target"
            print_usage
            exit 1
            ;;
    esac
    
    echo ""
    echo "================================================"
    print_status "green" "Build process completed successfully!"
}

# Print usage information
print_usage() {
    echo "Usage: $0 [TARGET] [ACTION]"
    echo ""
    echo "TARGETS:"
    echo "  proto       - Protobuf code generation only"
    echo "  java        - Java projects"
    echo "  cpp         - C++ projects"
    echo "  rust        - Rust projects"
    echo "  all         - All languages (default)"
    echo ""
    echo "ACTIONS:"
    echo "  build       - Build projects (default)"
    echo "  clean       - Clean build artifacts"
    echo "  rebuild     - Clean and rebuild projects"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Build all projects"
    echo "  $0 all clean          # Clean all projects"
    echo "  $0 java build         # Build only Java"
    echo "  $0 cpp rebuild        # Clean and rebuild C++"
    echo "  $0 proto generate     # Generate protobuf code only"
    echo ""
    echo "BACKWARD COMPATIBILITY:"
    echo "  $0 clean              # Clean all projects (old syntax)"
    echo "  $0 java               # Build Java projects (old syntax)"
}

main "$@"