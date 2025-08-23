#include "ads_client.h"
#include "../common/logging.h"
#include <iostream>
#include <thread>
#include <chrono>
#include <random>
#include <map>

static logging::Logger logger("CLIENT");

AdsClient::AdsClient(std::shared_ptr<Channel> channel)
    : stub_(AdsService::NewStub(channel)) {
}

AdsList AdsClient::getAds(const std::string& query, const std::string& asin_id, const std::string& understanding) {
    logging::Timer overall_timer("bidirectional_stream");
    ClientContext context;
    std::unique_ptr<ClientReaderWriter<Context, AdsList>> stream(stub_->GetAds(&context));
    
    std::string start_message = logging::LogContext()
        .add("query", query)
        .add("asin_id", asin_id)
        .add("understanding_provided", !understanding.empty())
        .build("Opening bidirectional stream");
    logger.info(start_message);
    
    // Send Context messages in a separate thread
    std::thread sender([this, &stream, &query, &asin_id, &understanding, &overall_timer]() {
        sendContextMessages(stream.get(), query, asin_id, understanding, overall_timer);
    });
    
    // Receive AdsList messages with timeout logic
    AdsList result = receiveAdsListWithTimeout(stream.get(), overall_timer);
    
    // Wait for sender thread to complete
    sender.join();
    
    // Finish the call
    Status status = stream->Finish();
    if (!status.ok()) {
        std::string error_message = logging::LogContext()
            .add("error_code", status.error_code())
            .add("error_message", status.error_message())
            .add("elapsed_ms", overall_timer.elapsed_ms())
            .build("GetAds RPC failed");
        logger.error(error_message);
    } else {
        std::string success_message = logging::LogContext()
            .add("total_duration_ms", overall_timer.elapsed_ms())
            .build("GetAds RPC completed successfully");
        logger.info(success_message);
    }
    
    return result;
}

void AdsClient::sendContextMessages(ClientReaderWriter<Context, AdsList>* stream,
                                  const std::string& query, 
                                  const std::string& asin_id, 
                                  const std::string& understanding,
                                  const logging::Timer& overall_timer) {
    // Send first Context message
    Context context1;
    context1.set_query(query);
    context1.set_asin_id(asin_id);
    context1.set_understanding(""); // Empty initially
    
    std::string first_context_message = logging::LogContext()
        .add("context_number", 1)
        .add("understanding_empty", true)
        .add("elapsed_ms", overall_timer.elapsed_ms())
        .build("Sending Context message");
    logger.info(first_context_message);
    
    if (stream->Write(context1)) {
        logger.debug("First Context message sent successfully");
    } else {
        logger.error("Failed to send first Context message");
        return;
    }
    
    // Wait 50ms before sending second message
    logger.debug("Waiting 50ms before second Context message");
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    
    // Send second Context message with understanding
    Context context2;
    context2.set_query(query);
    context2.set_asin_id(asin_id);
    context2.set_understanding(understanding);
    
    std::string second_context_message = logging::LogContext()
        .add("context_number", 2)
        .add("understanding_length", understanding.length())
        .add("elapsed_ms", overall_timer.elapsed_ms())
        .build("Sending Context message");
    logger.info(second_context_message);
    
    if (stream->Write(context2)) {
        logger.debug("Second Context message sent successfully");
    } else {
        logger.error("Failed to send second Context message");
        return;
    }
    
    // Half-close the stream (client side done sending)
    stream->WritesDone();
    
    std::string half_close_message = logging::LogContext()
        .add("elapsed_ms", overall_timer.elapsed_ms())
        .build("Half-closed client stream");
    logger.info(half_close_message);
}

AdsList AdsClient::receiveAdsListWithTimeout(ClientReaderWriter<Context, AdsList>* stream, 
                                            const logging::Timer& overall_timer) {
    std::map<uint32_t, AdsList> adsListBuffer; // Buffer by version number
    AdsList currentAdsList;
    
    // Generate random timeout (30-120ms jittered)
    int timeoutMs = generateRandomTimeout();
    std::string timeout_message = logging::LogContext()
        .add("timeout_ms", timeoutMs)
        .add("min_timeout", 30)
        .add("max_timeout", 120)
        .build("Generated random timeout for result selection");
    logger.info(timeout_message);
    
    auto startTime = std::chrono::steady_clock::now();
    auto timeoutDuration = std::chrono::milliseconds(timeoutMs);
    
    // Read AdsList messages until timeout
    while (true) {
        auto currentTime = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(currentTime - startTime);
        
        if (elapsed >= timeoutDuration) {
            std::string timeout_reached_message = logging::LogContext()
                .add("timeout_ms", timeoutMs)
                .add("elapsed_ms", overall_timer.elapsed_ms())
                .add("versions_received", adsListBuffer.size())
                .build("Timeout reached, proceeding with available results");
            logger.info(timeout_reached_message);
            break;
        }
        
        AdsList adsList;
        if (stream->Read(&adsList)) {
            uint32_t version = adsList.version();
            bool is_replacement = adsListBuffer.find(version) != adsListBuffer.end();
            
            std::string receive_message = logging::LogContext()
                .add("version", version)
                .add("ads_count", adsList.ads_size())
                .add("elapsed_ms", overall_timer.elapsed_ms())
                .add("is_replacement", is_replacement)
                .build("Received AdsList");
            logger.info(receive_message);
            
            // Log debug details about the ads if debug level is enabled
            if (logger.is_debug_enabled()) {
                for (int i = 0; i < adsList.ads_size(); i++) {
                    const auto& ad = adsList.ads(i);
                    std::string ad_message = logging::LogContext()
                        .add("version", version)
                        .add("ad_index", i)
                        .add("asin_id", ad.asin_id())
                        .add("ad_id", ad.ad_id())
                        .add("score", ad.score())
                        .build("Ad details");
                    logger.debug(ad_message);
                }
            }
            
            // Buffer the AdsList by version (replace older versions)
            if (is_replacement) {
                std::string replace_message = logging::LogContext()
                    .add("version", version)
                    .add("old_ads_count", adsListBuffer[version].ads_size())
                    .add("new_ads_count", adsList.ads_size())
                    .build("Replaced AdsList in buffer");
                logger.debug(replace_message);
            }
            
            adsListBuffer[version] = adsList;
            currentAdsList = adsList; // Keep track of the most recent
        } else {
            // Stream ended, break out of loop
            std::string stream_end_message = logging::LogContext()
                .add("elapsed_ms", overall_timer.elapsed_ms())
                .add("versions_received", adsListBuffer.size())
                .build("Stream ended");
            logger.info(stream_end_message);
            break;
        }
    }
    
    // Log buffer state for debugging
    std::ostringstream versions_oss;
    for (const auto& pair : adsListBuffer) {
        if (versions_oss.tellp() > 0) versions_oss << ",";
        versions_oss << pair.first;
    }
    
    std::string buffer_state_message = logging::LogContext()
        .add("buffer_size", adsListBuffer.size())
        .add("available_versions", versions_oss.str())
        .add("elapsed_ms", overall_timer.elapsed_ms())
        .build("Buffer state at timeout");
    logger.debug(buffer_state_message);
    
    // Return the latest version available
    if (!adsListBuffer.empty()) {
        auto latestEntry = adsListBuffer.rbegin(); // Get highest version
        uint32_t finalVersion = latestEntry->first;
        AdsList finalResult = latestEntry->second;
        
        std::string final_result_message = logging::LogContext()
            .add("selected_version", finalVersion)
            .add("ads_count", finalResult.ads_size())
            .add("total_duration_ms", overall_timer.elapsed_ms())
            .add("versions_considered", adsListBuffer.size())
            .build("FINAL RESULT: Selected AdsList");
        logger.info(final_result_message);
        
        // Log performance summary
        std::string perf_message = logging::LogContext()
            .add("operation", "bidirectional_stream")
            .add("total_duration_ms", overall_timer.elapsed_ms())
            .add("timeout_used_ms", timeoutMs)
            .add("versions_received", adsListBuffer.size())
            .add("final_version", finalVersion)
            .build("Performance summary");
        logger.info(perf_message);
        
        return finalResult;
    } else {
        std::string no_result_message = logging::LogContext()
            .add("total_duration_ms", overall_timer.elapsed_ms())
            .add("timeout_ms", timeoutMs)
            .add("buffer_size", adsListBuffer.size())
            .build("FINAL RESULT: No AdsList received within timeout");
        logger.warn(no_result_message);
        return AdsList(); // Return empty AdsList
    }
}

int AdsClient::generateRandomTimeout() {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<> dis(30, 120);
    return dis(gen);
}

void AdsClient::shutdown() {
    // Nothing specific to clean up for this implementation
    logger.info("Client shutdown completed");
}