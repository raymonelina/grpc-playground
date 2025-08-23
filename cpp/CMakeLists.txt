cmake_minimum_required(VERSION 3.16)
project(grpc-ads-cpp)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required packages
find_package(Threads REQUIRED)
find_package(PkgConfig REQUIRED)
find_package(Protobuf REQUIRED)

# Use pkg-config to find gRPC
pkg_check_modules(GRPC REQUIRED grpc++)

# Find protoc executable
find_program(PROTOC_EXECUTABLE protoc REQUIRED)

# Find grpc_cpp_plugin
find_program(GRPC_CPP_PLUGIN grpc_cpp_plugin REQUIRED)

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
    COMMAND ${PROTOC_EXECUTABLE}
    ARGS --grpc_out "${GENERATED_PROTOBUF_PATH}"
         --cpp_out "${GENERATED_PROTOBUF_PATH}"
         -I "${PROTO_PATH}"
         --plugin=protoc-gen-grpc="${GRPC_CPP_PLUGIN}"
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
    protobuf::libprotobuf
    ${GRPC_LDFLAGS}
)

target_include_directories(ads_proto PUBLIC 
    ${GENERATED_PROTOBUF_PATH}
    ${Protobuf_INCLUDE_DIRS}
    ${GRPC_INCLUDE_DIRS}
)

target_compile_options(ads_proto PUBLIC 
    ${GRPC_CFLAGS_OTHER}
)



# Add subdirectories for client and server
add_subdirectory(client)
add_subdirectory(server)
