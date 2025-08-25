#!/bin/bash

# Script to generate protobuf and gRPC code for all languages
# This script generates Java, C++, and Rust code from the ads.proto file
# Supports clean, regenerate, and selective generation

# Exit immediately if any command fails
set -e

# Source common utilities
source "$(dirname "$0")/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROTO_DIR="$PROJECT_ROOT/proto"
PROTO_FILE="$PROTO_DIR/ads.proto"

# Source common utilities
source "$SCRIPT_DIR/common.sh"

# Function to clean generated code
clean_generated() {
    local language="$1"
    
    case "$language" in
        java)
            print_status "blue" "Cleaning Java generated code..."
            rm -rf "$PROJECT_ROOT/java/generated"
            rm -rf "$PROJECT_ROOT/java/target/generated-sources/protobuf"
            ;;
        cpp)
            print_status "blue" "Cleaning C++ generated code..."
            rm -rf "$PROJECT_ROOT/cpp/generated"
            ;;
        rust)
            print_status "blue" "Cleaning Rust generated code..."
            rm -rf "$PROJECT_ROOT/rust/generated"
            rm -f "$PROJECT_ROOT/rust/build.rs.template"
            # Clean Rust build artifacts that contain generated code
            find "$PROJECT_ROOT/rust" -name "target" -type d -exec rm -rf {} + 2>/dev/null || true
            ;;
        all)
            print_status "blue" "Cleaning all generated code..."
            clean_generated java
            clean_generated cpp
            clean_generated rust
            ;;
    esac
}

# Generate Java code
generate_java() {
    print_status "blue" "Generating Java code..."
    
    JAVA_OUT_DIR="$PROJECT_ROOT/java/generated"
    mkdir -p "$JAVA_OUT_DIR"
    
    if ! command_exists protoc; then
        print_status "red" "protoc not found. Please install Protocol Buffers compiler."
        exit 1
    fi
    
    # Check for gRPC Java plugin
    if ! command_exists protoc-gen-grpc-java; then
        print_status "yellow" "protoc-gen-grpc-java not found. Trying alternative locations..."
        # Try common locations for the plugin
        local grpc_plugin=""
        for path in "/usr/local/bin/protoc-gen-grpc-java" "/opt/homebrew/bin/protoc-gen-grpc-java" "$(which protoc-gen-grpc-java 2>/dev/null)"; do
            if [ -x "$path" ]; then
                grpc_plugin="$path"
                break
            fi
        done
        
        if [ -z "$grpc_plugin" ]; then
            print_status "red" "gRPC Java plugin not found. Please install grpc-java."
            exit 1
        fi
    else
        grpc_plugin="$(which protoc-gen-grpc-java)"
    fi
    
    # Generate Java protobuf and gRPC code
    if protoc --proto_path="$PROTO_DIR" \
           --java_out="$JAVA_OUT_DIR" \
           --grpc-java_out="$JAVA_OUT_DIR" \
           --plugin=protoc-gen-grpc-java="$grpc_plugin" \
           "$PROTO_FILE"; then
        print_status "green" "Java code generated in $JAVA_OUT_DIR"
        
        # List generated files
        find "$JAVA_OUT_DIR" -name "*.java" | while read -r file; do
            print_status "blue" "  Generated: $(basename "$file")"
        done
    else
        print_status "red" "Failed to generate Java code"
        exit 1
    fi
}

# Generate C++ code
generate_cpp() {
    print_status "blue" "Generating C++ code..."
    
    CPP_OUT_DIR="$PROJECT_ROOT/cpp/generated"
    mkdir -p "$CPP_OUT_DIR"
    
    if ! command_exists protoc; then
        print_status "red" "protoc not found. Please install Protocol Buffers compiler."
        exit 1
    fi
    
    # Check for gRPC C++ plugin
    if ! command_exists grpc_cpp_plugin; then
        print_status "yellow" "grpc_cpp_plugin not found. Trying alternative locations..."
        # Try common locations for the plugin
        local grpc_plugin=""
        for path in "/usr/local/bin/grpc_cpp_plugin" "/opt/homebrew/bin/grpc_cpp_plugin" "$(which grpc_cpp_plugin 2>/dev/null)"; do
            if [ -x "$path" ]; then
                grpc_plugin="$path"
                break
            fi
        done
        
        if [ -z "$grpc_plugin" ]; then
            print_status "red" "gRPC C++ plugin not found. Please install grpc."
            exit 1
        fi
    else
        grpc_plugin="$(which grpc_cpp_plugin)"
    fi
    
    # Generate C++ protobuf and gRPC code
    if protoc --proto_path="$PROTO_DIR" \
           --cpp_out="$CPP_OUT_DIR" \
           --grpc_out="$CPP_OUT_DIR" \
           --plugin=protoc-gen-grpc="$grpc_plugin" \
           "$PROTO_FILE"; then
        print_status "green" "C++ code generated in $CPP_OUT_DIR"
        
        # List generated files
        find "$CPP_OUT_DIR" -name "*.h" -o -name "*.cc" | while read -r file; do
            print_status "blue" "  Generated: $(basename "$file")"
        done
    else
        print_status "red" "Failed to generate C++ code"
        exit 1
    fi
}

# Generate Rust code
generate_rust() {
    print_status "blue" "Generating Rust code..."
    
    RUST_OUT_DIR="$PROJECT_ROOT/rust/generated"
    mkdir -p "$RUST_OUT_DIR"
    
    # For Rust, we'll use build.rs files in each Rust project
    # Create a build.rs template that can be used by both client and server
    cat > "$PROJECT_ROOT/rust/build.rs.template" << 'EOF'
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("../proto/ads.proto")?;
    Ok(())
}
EOF
    
    # Ensure build.rs files exist in client and server projects
    for project in client server; do
        local build_rs_path="$PROJECT_ROOT/rust/$project/build.rs"
        if [ ! -f "$build_rs_path" ]; then
            cp "$PROJECT_ROOT/rust/build.rs.template" "$build_rs_path"
            print_status "blue" "  Created build.rs for $project"
        fi
    done
    
    # Verify Rust projects can generate code by running cargo check
    if command_exists cargo; then
        print_status "blue" "Verifying Rust code generation..."
        
        for project in client server; do
            cd "$PROJECT_ROOT/rust/$project"
            if cargo check --quiet 2>/dev/null; then
                print_status "green" "  Rust $project code generation verified"
            else
                print_status "yellow" "  Rust $project code generation may have issues (check dependencies)"
            fi
        done
        
        cd "$PROJECT_ROOT"
    else
        print_status "yellow" "Cargo not found. Rust code generation setup complete but not verified."
    fi
    
    print_status "green" "Rust build template created. Individual Rust projects will use build.rs for code generation."
}

# Main execution
main() {
    local action="${1:-all}"
    local language="${2:-all}"
    
    # Print header
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - Proto Code Generator"
    echo "=================================================="
    print_status "blue" "Project root: $PROJECT_ROOT"
    print_status "blue" "Proto file: $PROTO_FILE"
    echo ""
    
    # Check if proto file exists
    if [ ! -f "$PROTO_FILE" ]; then
        print_status "red" "Proto file not found at $PROTO_FILE"
        exit 1
    fi
    
    case "$action" in
        clean)
            clean_generated "$language"
            print_status "green" "Clean completed successfully!"
            ;;
        generate)
            case "$language" in
                java)
                    generate_java
                    ;;
                cpp)
                    generate_cpp
                    ;;
                rust)
                    generate_rust
                    ;;
                all)
                    generate_java
                    generate_cpp
                    generate_rust
                    ;;
                *)
                    print_usage
                    exit 1
                    ;;
            esac
            print_status "green" "Code generation completed successfully!"
            ;;
        regenerate)
            print_status "blue" "Regenerating code (clean + generate)..."
            clean_generated "$language"
            echo ""
            case "$language" in
                java)
                    generate_java
                    ;;
                cpp)
                    generate_cpp
                    ;;
                rust)
                    generate_rust
                    ;;
                all)
                    generate_java
                    generate_cpp
                    generate_rust
                    ;;
                *)
                    print_usage
                    exit 1
                    ;;
            esac
            print_status "green" "Code regeneration completed successfully!"
            ;;
        java|cpp|rust|all)
            # Backward compatibility - treat language as action
            case "$action" in
                java)
                    generate_java
                    ;;
                cpp)
                    generate_cpp
                    ;;
                rust)
                    generate_rust
                    ;;
                all)
                    generate_java
                    generate_cpp
                    generate_rust
                    ;;
            esac
            print_status "green" "Code generation completed successfully!"
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
    echo "Usage: $0 [ACTION] [LANGUAGE]"
    echo ""
    echo "ACTIONS:"
    echo "  generate    - Generate protobuf code (default)"
    echo "  clean       - Clean generated code"
    echo "  regenerate  - Clean and regenerate code"
    echo "  help        - Show this help message"
    echo ""
    echo "LANGUAGES:"
    echo "  java        - Java only"
    echo "  cpp         - C++ only"
    echo "  rust        - Rust only"
    echo "  all         - All languages (default)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Generate code for all languages"
    echo "  $0 generate java      # Generate only Java code"
    echo "  $0 clean all          # Clean all generated code"
    echo "  $0 regenerate cpp     # Clean and regenerate C++ code"
    echo ""
    echo "BACKWARD COMPATIBILITY:"
    echo "  $0 java               # Generate Java code (old syntax)"
    echo "  $0 all                # Generate all code (old syntax)"
}

main "$@"
