#!/bin/bash

# Build script for Rust projects
# Supports build, clean, and rebuild operations

set -e

# Source common utilities
source "$(dirname "$0")/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/rust"

# Function to check if command exists


# Function to clean Rust build artifacts
clean_rust() {
    print_status "blue" "Cleaning Rust build artifacts..."
    
    cd "$RUST_DIR"
    
    # Clean workspace
    if command_exists cargo; then
        cargo clean >/dev/null 2>&1 || true
    fi
    
    # Manual cleanup of target directories
    rm -rf target/
    rm -rf client/target/
    rm -rf server/target/
    
    print_status "green" "Rust clean completed"
}

# Function to create Rust workspace structure
create_rust_workspace() {
    print_status "yellow" "Creating Rust workspace..."
    
    cat > "$RUST_DIR/Cargo.toml" << 'EOF'
[workspace]
members = ["client", "server"]
resolver = "2"

[workspace.dependencies]
tonic = "0.10"
prost = "0.12"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }
tonic-build = "0.10"
EOF

    # Create client project
    mkdir -p "$RUST_DIR/client/src"
    if [ ! -f "$RUST_DIR/client/Cargo.toml" ]; then
        cat > "$RUST_DIR/client/Cargo.toml" << 'EOF'
[package]
name = "ads-client"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic.workspace = true
prost.workspace = true
tokio.workspace = true

[build-dependencies]
tonic-build.workspace = true
EOF

        cat > "$RUST_DIR/client/build.rs" << 'EOF'
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("../../proto/ads.proto")?;
    Ok(())
}
EOF

        cat > "$RUST_DIR/client/src/main.rs" << 'EOF'
// Placeholder for client implementation
fn main() {
    println!("Ads client - to be implemented");
}
EOF

        print_status "green" "Created Rust client project"
    fi

    # Create server project
    mkdir -p "$RUST_DIR/server/src"
    if [ ! -f "$RUST_DIR/server/Cargo.toml" ]; then
        cat > "$RUST_DIR/server/Cargo.toml" << 'EOF'
[package]
name = "ads-server"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic.workspace = true
prost.workspace = true
tokio.workspace = true

[build-dependencies]
tonic-build.workspace = true
EOF

        cat > "$RUST_DIR/server/build.rs" << 'EOF'
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("../../proto/ads.proto")?;
    Ok(())
}
EOF

        cat > "$RUST_DIR/server/src/main.rs" << 'EOF'
// Placeholder for server implementation
fn main() {
    println!("Ads server - to be implemented");
}
EOF

        print_status "green" "Created Rust server project"
    fi
    
    print_status "green" "Created Rust workspace"
}

# Function to build Rust projects
build_rust() {
    print_status "blue" "Building Rust projects..."
    
    # Check for Cargo
    if ! command_exists cargo; then
        print_status "red" "Cargo not found. Please install Rust and Cargo."
        exit 1
    fi

    # Create workspace if it doesn't exist
    if [ ! -f "$RUST_DIR/Cargo.toml" ]; then
        create_rust_workspace
    fi

    # Build the workspace
    cd "$RUST_DIR"

    # This will trigger the build.rs scripts and generate the protobuf code
    if cargo build; then
        print_status "green" "Rust build completed successfully"
        print_status "blue" "Protobuf code has been generated via build.rs scripts"
        
        # List built binaries
        if [ -f "target/debug/ads-client" ]; then
            print_status "blue" "  Built: target/debug/ads-client"
        fi
        if [ -f "target/debug/ads-server" ]; then
            print_status "blue" "  Built: target/debug/ads-server"
        fi
    else
        print_status "red" "Rust build failed"
        exit 1
    fi
}

# Main execution
main() {
    local action="${1:-build}"
    
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - Rust Build Script"
    echo "=================================================="
    print_status "blue" "Rust directory: $RUST_DIR"
    echo ""
    
    case "$action" in
        build)
            build_rust
            ;;
        clean)
            clean_rust
            ;;
        rebuild)
            print_status "blue" "Rebuilding Rust projects (clean + build)..."
            clean_rust
            echo ""
            build_rust
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
    
    print_status "green" "Rust build script completed successfully!"
}

# Print usage information
print_usage() {
    echo "Usage: $0 [ACTION]"
    echo ""
    echo "ACTIONS:"
    echo "  build       - Build Rust projects (default)"
    echo "  clean       - Clean build artifacts"
    echo "  rebuild     - Clean and rebuild projects"
    echo "  help        - Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0              # Build Rust projects"
    echo "  $0 clean        # Clean build artifacts"
    echo "  $0 rebuild      # Clean and rebuild"
}

main "$@"
