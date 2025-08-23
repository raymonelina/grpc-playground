#pragma once

#include <memory>
#include <string>
#include <vector>
#include <mutex>
#include <condition_variable>
#include <grpcpp/grpcpp.h>
#include "ads.grpc.pb.h"
#include "../common/logging.h"

using grpc::Channel;
using grpc::ClientContext;
using grpc::ClientReaderWriter;
using grpc::Status;
using ads::Context;
using ads::AdsList;
using ads::AdsService;

class AdsClient {
public:
    AdsClient(std::shared_ptr<Channel> channel);
    
    // Main method to get ads with bidirectional streaming
    AdsList getAds(const std::string& query, const std::string& asin_id, const std::string& understanding);
    
    // Shutdown the client
    void shutdown();

private:
    std::unique_ptr<AdsService::Stub> stub_;
    
    // Helper methods
    void sendContextMessages(ClientReaderWriter<Context, AdsList>* stream,
                           const std::string& query, 
                           const std::string& asin_id, 
                           const std::string& understanding,
                           const logging::Timer& overall_timer);
    
    AdsList receiveAdsListWithTimeout(ClientReaderWriter<Context, AdsList>* stream,
                                     const logging::Timer& overall_timer);
    
    // Random timeout generation (30-120ms jittered)
    int generateRandomTimeout();
};