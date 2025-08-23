#!/bin/bash

# Build script for C++ projects
# Supports build, clean, and rebuild operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CPP_DIR="$PROJECT_ROOT/cpp"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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
        *) echo "$message" ;;
    esac
}

# Function to clean C++ build artifacts
clean_cpp() {
    print_status "blue" "Cleaning C++ build artifacts..."
    
    cd "$CPP_DIR"
    
    # Remove build directories
    rm -rf build/
    rm -rf cmake-build-*/
    rm -rf out/
    
    # Remove generated files if they exist outside build directory
    rm -rf generated/
    
    print_status "green" "C++ clean completed"
}

# Function to create CMake project structure
create_cmake_project() {
    print_status "yellow" "Creating CMakeLists.txt..."
    
    cat > "$CPP_DIR/CMakeLists.txt" << 'EOF'
cmake_minimum_required(VERSION 3.16)
project(grpc-ads-cpp)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required packages
find_package(Threads REQUIRED)
find_package(PkgConfig REQUIRED)
find_package(Protobuf REQUIRED)
find_package(gRPC REQUIRED)

# Proto file
set(PROTO_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../proto")
set(ADS_PROTO "${PROTO_PATH}/ads.proto")

# Generated sources
set(GENERATED_PROTOBUF_PATH "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY ${GENERATED_PROTOBUF_PATH})

set(ADS_PB_CPP_FILE "${GENERATED_PROTOBUF_PATH}/ads.pb.cc")
set(ADS_PB_H_FILE "${GENERATED_PROTOBUF_PATH}/ads.pb.h")
set(ADS_GRPC_PB_CPP_FILE "${GENERATED_PROTOBUF_PATH}/ads.grpc.pb.cc")
set(ADS_GRPC_PB_H_FILE "${GENERATED_PROTOBUF_PATH}/ads.grpc.pb.h")

# Custom command to generate protobuf and gRPC files
add_custom_command(
    OUTPUT "${ADS_PB_CPP_FILE}" "${ADS_PB_H_FILE}" "${ADS_GRPC_PB_CPP_FILE}" "${ADS_GRPC_PB_H_FILE}"
    COMMAND ${Protobuf_PROTOC_EXECUTABLE}
    ARGS --grpc_out "${GENERATED_PROTOBUF_PATH}"
         --cpp_out "${GENERATED_PROTOBUF_PATH}"
         -I "${PROTO_PATH}"
         --plugin=protoc-gen-grpc="${gRPC_CPP_PLUGIN_EXECUTABLE}"
         "${ADS_PROTO}"
    DEPENDS "${ADS_PROTO}"
    COMMENT "Generating protobuf and gRPC files"
)

# Create a library for the generated files
add_library(ads_proto
    ${ADS_PB_CPP_FILE}
    ${ADS_GRPC_PB_CPP_FILE}
)

target_link_libraries(ads_proto
    ${Protobuf_LIBRARIES}
    gRPC::grpc++
    gRPC::grpc++_reflection
)

target_include_directories(ads_proto PUBLIC ${GENERATED_PROTOBUF_PATH})

# Add subdirectories for client and server
add_subdirectory(client)
add_subdirectory(server)
EOF

    # Create client CMakeLists.txt
    mkdir -p "$CPP_DIR/client"
    if [ ! -f "$CPP_DIR/client/CMakeLists.txt" ]; then
        cat > "$CPP_DIR/client/CMakeLists.txt" << 'EOF'
# Client executable
add_executable(ads_client
    ads_client.cpp
    ads_client.h
    main.cpp
)

target_link_libraries(ads_client
    ads_proto
    Threads::Threads
)

target_include_directories(ads_client PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${GENERATED_PROTOBUF_PATH}
)
EOF
    fi

    # Create server CMakeLists.txt
    mkdir -p "$CPP_DIR/server"
    if [ ! -f "$CPP_DIR/server/CMakeLists.txt" ]; then
        cat > "$CPP_DIR/server/CMakeLists.txt" << 'EOF'
# Server executable
add_executable(ads_server
    ads_service_impl.cpp
    ads_service_impl.h
    ad_generator.cpp
    ad_generator.h
    main.cpp
)

target_link_libraries(ads_server
    ads_proto
    Threads::Threads
)

target_include_directories(ads_server PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${GENERATED_PROTOBUF_PATH}
)
EOF
    fi
    
    print_status "green" "Created CMake project structure"
}

# Function to build C++ projects
build_cpp() {
    print_status "blue" "Building C++ projects..."
    
    # Check for required tools
    if ! command_exists cmake; then
        print_status "red" "CMake not found. Please install CMake."
        exit 1
    fi

    # Create CMakeLists.txt if it doesn't exist
    if [ ! -f "$CPP_DIR/CMakeLists.txt" ]; then
        create_cmake_project
    fi

    # Build the project
    cd "$CPP_DIR"

    # Create build directory
    mkdir -p build
    cd build

    # Configure and build
    if cmake ..; then
        print_status "green" "CMake configuration completed"
    else
        print_status "red" "CMake configuration failed"
        exit 1
    fi
    
    # Build the protobuf library and any available executables
    if make -j$(nproc 2>/dev/null || echo 4); then
        print_status "green" "C++ build completed successfully"
        print_status "blue" "Generated protobuf files are available in the build/generated directory"
        
        # List built targets
        if [ -f "libads_proto.a" ]; then
            print_status "blue" "  Built: libads_proto.a"
        fi
        if [ -f "client/ads_client" ]; then
            print_status "blue" "  Built: client/ads_client"
        fi
        if [ -f "server/ads_server" ]; then
            print_status "blue" "  Built: server/ads_server"
        fi
    else
        print_status "red" "C++ build failed"
        exit 1
    fi
}

# Main execution
main() {
    local action="${1:-build}"
    
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - C++ Build Script"
    echo "=================================================="
    print_status "blue" "C++ directory: $CPP_DIR"
    echo ""
    
    case "$action" in
        build)
            build_cpp
            ;;
        clean)
            clean_cpp
            ;;
        rebuild)
            print_status "blue" "Rebuilding C++ projects (clean + build)..."
            clean_cpp
            echo ""
            build_cpp
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
    
    print_status "green" "C++ build script completed successfully!"
}

# Print usage information
print_usage() {
    echo "Usage: $0 [ACTION]"
    echo ""
    echo "ACTIONS:"
    echo "  build       - Build C++ projects (default)"
    echo "  clean       - Clean build artifacts"
    echo "  rebuild     - Clean and rebuild projects"
    echo "  help        - Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0              # Build C++ projects"
    echo "  $0 clean        # Clean build artifacts"
    echo "  $0 rebuild      # Clean and rebuild"
}

main "$@"