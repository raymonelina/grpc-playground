# Server executable
add_executable(ads_server 
    main.cpp
    ads_service_impl.cpp
    ad_generator.cpp
)

target_link_libraries(ads_server 
    ads_proto
    protobuf::libprotobuf
    ${GRPC_LDFLAGS}
    Threads::Threads
)

target_include_directories(ads_server PRIVATE
    ${GENERATED_PROTOBUF_PATH}
    ${Protobuf_INCLUDE_DIRS}
    ${GRPC_INCLUDE_DIRS}
)

target_compile_options(ads_server PRIVATE
    ${GRPC_CFLAGS_OTHER}
)
