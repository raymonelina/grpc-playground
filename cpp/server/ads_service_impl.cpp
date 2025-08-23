#include "ads_service_impl.h"
#include "../common/logging.h"
#include <iostream>
#include <thread>
#include <chrono>
#include <atomic>

static logging::Logger logger("SERVER");
static std::atomic<long> session_counter(0);

Status AdsServiceImpl::GetAds(ServerContext* context,
                              ServerReaderWriter<AdsList, Context>* stream) {
    long session_id = session_counter.fetch_add(1) + 1;
    logging::Timer session_timer("session_" + std::to_string(session_id));
    
    std::string session_start_message = logging::LogContext()
        .add("session_id", session_id)
        .add("thread", std::this_thread::get_id())
        .build("New bidirectional stream opened");
    logger.info(session_start_message);
    
    Context client_context;
    int context_count = 0;
    
    // Read Context messages from client
    while (stream->Read(&client_context)) {
        context_count++;
        logging::Timer context_processing_timer("context_processing");
        
        std::string context_message = logging::LogContext()
            .add("session_id", session_id)
            .add("context_number", context_count)
            .add("query", client_context.query())
            .add("asin_id", client_context.asin_id())
            .add("understanding_length", static_cast<int>(client_context.understanding().length()))
            .add("understanding_empty", client_context.understanding().empty())
            .add("session_elapsed_ms", session_timer.elapsed_ms())
            .build("Received Context message");
        logger.info(context_message);
        
        try {
            if (context_count == 1) {
                // Send AdsList version 1 immediately
                logging::Timer ad_gen_timer("ad_generation_v1");
                AdsList ads_v1 = ad_generator_.generateAds(client_context, 1);
                
                std::string send_message = logging::LogContext()
                    .add("session_id", session_id)
                    .add("version", 1)
                    .add("ads_count", ads_v1.ads_size())
                    .add("generation_ms", ad_gen_timer.elapsed_ms())
                    .add("context_processing_ms", context_processing_timer.elapsed_ms())
                    .build("Sending AdsList");
                logger.info(send_message);
                
                stream->Write(ads_v1);
                
                // Log debug details about the ads if debug level is enabled
                if (logger.is_debug_enabled()) {
                    for (int i = 0; i < ads_v1.ads_size(); i++) {
                        const auto& ad = ads_v1.ads(i);
                        std::string ad_message = logging::LogContext()
                            .add("session_id", session_id)
                            .add("version", 1)
                            .add("ad_index", i)
                            .add("asin_id", ad.asin_id())
                            .add("ad_id", ad.ad_id())
                            .add("score", ad.score())
                            .build("Generated ad details");
                        logger.debug(ad_message);
                    }
                }
                
            } else if (context_count == 2) {
                // Send AdsList version 2 immediately
                logging::Timer ad_gen_timer("ad_generation_v2");
                AdsList ads_v2 = ad_generator_.generateAds(client_context, 2);
                
                std::string send_message = logging::LogContext()
                    .add("session_id", session_id)
                    .add("version", 2)
                    .add("ads_count", ads_v2.ads_size())
                    .add("generation_ms", ad_gen_timer.elapsed_ms())
                    .add("context_processing_ms", context_processing_timer.elapsed_ms())
                    .build("Sending AdsList");
                logger.info(send_message);
                
                stream->Write(ads_v2);
                
                // Log debug details about the ads if debug level is enabled
                if (logger.is_debug_enabled()) {
                    for (int i = 0; i < ads_v2.ads_size(); i++) {
                        const auto& ad = ads_v2.ads(i);
                        std::string ad_message = logging::LogContext()
                            .add("session_id", session_id)
                            .add("version", 2)
                            .add("ad_index", i)
                            .add("asin_id", ad.asin_id())
                            .add("ad_id", ad.ad_id())
                            .add("score", ad.score())
                            .build("Generated ad details");
                        logger.debug(ad_message);
                    }
                }
                
                // Schedule version 3 after 50ms delay
                std::string schedule_message = logging::LogContext()
                    .add("session_id", session_id)
                    .add("delay_ms", 50)
                    .build("Scheduling delayed version 3 AdsList");
                logger.info(schedule_message);
                
                std::thread([this, stream, client_context, session_id, &session_timer, context_count]() {
                    std::this_thread::sleep_for(std::chrono::milliseconds(50));
                    
                    try {
                        logging::Timer final_ad_gen_timer("ad_generation_v3");
                        AdsList ads_v3 = ad_generator_.generateAds(client_context, 3);
                        
                        std::string final_send_message = logging::LogContext()
                            .add("session_id", session_id)
                            .add("version", 3)
                            .add("ads_count", ads_v3.ads_size())
                            .add("generation_ms", final_ad_gen_timer.elapsed_ms())
                            .add("session_elapsed_ms", session_timer.elapsed_ms())
                            .build("Sending delayed AdsList");
                        logger.info(final_send_message);
                        
                        stream->Write(ads_v3);
                        
                        // Log debug details about the ads if debug level is enabled
                        if (logger.is_debug_enabled()) {
                            for (int i = 0; i < ads_v3.ads_size(); i++) {
                                const auto& ad = ads_v3.ads(i);
                                std::string ad_message = logging::LogContext()
                                    .add("session_id", session_id)
                                    .add("version", 3)
                                    .add("ad_index", i)
                                    .add("asin_id", ad.asin_id())
                                    .add("ad_id", ad.ad_id())
                                    .add("score", ad.score())
                                    .build("Generated ad details");
                                logger.debug(ad_message);
                            }
                        }
                        
                        std::string completion_message = logging::LogContext()
                            .add("session_id", session_id)
                            .add("total_contexts", context_count)
                            .add("total_duration_ms", session_timer.elapsed_ms())
                            .build("Stream completed successfully");
                        logger.info(completion_message);
                        
                    } catch (const std::exception& e) {
                        std::string error_message = logging::LogContext()
                            .add("session_id", session_id)
                            .add("error_type", "std::exception")
                            .add("error_message", e.what())
                            .add("session_elapsed_ms", session_timer.elapsed_ms())
                            .build("Error sending version 3");
                        logger.error(error_message);
                    }
                }).detach();
                
                break; // Client should half-close after second context
            }
        } catch (const std::exception& e) {
            std::string processing_error_message = logging::LogContext()
                .add("session_id", session_id)
                .add("context_number", context_count)
                .add("error_type", "std::exception")
                .add("error_message", e.what())
                .add("processing_ms", context_processing_timer.elapsed_ms())
                .build("Error processing Context message");
            logger.error(processing_error_message);
            return Status(grpc::StatusCode::INTERNAL, "Error processing context");
        }
    }
    
    // Wait a bit for the delayed version 3 to be sent
    std::this_thread::sleep_for(std::chrono::milliseconds(60));
    
    std::string client_disconnect_message = logging::LogContext()
        .add("session_id", session_id)
        .add("contexts_received", context_count)
        .add("session_elapsed_ms", session_timer.elapsed_ms())
        .build("Client half-closed stream");
    logger.info(client_disconnect_message);
    
    return Status::OK;
}