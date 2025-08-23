# C++ Client executable
add_executable(ads_client 
    main.cpp
    ads_client.cpp
)

target_link_libraries(ads_client 
    ads_proto
    ${GRPC_LDFLAGS}
    Threads::Threads
)

target_include_directories(ads_client PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${GENERATED_PROTOBUF_PATH}
    ${Protobuf_INCLUDE_DIRS}
    ${GRPC_INCLUDE_DIRS}
)

target_compile_options(ads_client PRIVATE
    ${GRPC_CFLAGS_OTHER}
)
