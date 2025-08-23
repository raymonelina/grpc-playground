#include <iostream>
#include <memory>
#include <string>
#include <grpcpp/grpcpp.h>
#include "ads_client.h"

using grpc::Channel;
using grpc::CreateChannel;
using grpc::InsecureChannelCredentials;

void RunClient() {
    std::string server_address("localhost:50051");
    
    // Create channel to server
    std::shared_ptr<Channel> channel = CreateChannel(server_address, InsecureChannelCredentials());
    AdsClient client(channel);
    
    std::cout << "C++ Client connecting to " << server_address << std::endl;
    
    // Test parameters
    std::string query = "coffee maker";
    std::string asin_id = "B000123456";
    std::string understanding = "user wants high-quality coffee brewing equipment";
    
    try {
        // Call the bidirectional streaming method
        AdsList result = client.getAds(query, asin_id, understanding);
        
        // Display results
        if (result.ads_size() > 0) {
            std::cout << "\n=== Final Result ===" << std::endl;
            std::cout << "AdsList version: " << result.version() << std::endl;
            std::cout << "Number of ads: " << result.ads_size() << std::endl;
            
            for (int i = 0; i < result.ads_size(); ++i) {
                const auto& ad = result.ads(i);
                std::cout << "Ad " << (i + 1) << ": asin_id=" << ad.asin_id() 
                          << ", ad_id=" << ad.ad_id() 
                          << ", score=" << ad.score() << std::endl;
            }
        } else {
            std::cout << "No ads received" << std::endl;
        }
        
    } catch (const std::exception& e) {
        std::cerr << "Exception: " << e.what() << std::endl;
    }
    
    client.shutdown();
}

int main(int argc, char** argv) {
    RunClient();
    return 0;
}