package com.example.ads.server;

import ads.Ads;
import ads.AdsServiceGrpc;
import com.example.ads.common.LoggingConfig;
import io.grpc.stub.StreamObserver;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.logging.Logger;

/**
 * Implementation of the AdsService gRPC bidirectional streaming service.
 * Handles Context messages from clients and responds with AdsList messages.
 */
public class AdsServiceImpl extends AdsServiceGrpc.AdsServiceImplBase {
    private static final Logger logger = LoggingConfig.configureLogger(AdsServiceImpl.class, "SERVER");
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(4);
    private final AdGenerator adGenerator = new AdGenerator();
    private final AtomicLong sessionCounter = new AtomicLong(0);
    
    @Override
    public StreamObserver<Ads.Context> getAds(StreamObserver<Ads.AdsList> responseObserver) {
        long sessionId = sessionCounter.incrementAndGet();
        LoggingConfig.Timer sessionTimer = new LoggingConfig.Timer("session_" + sessionId);
        
        String sessionStartMessage = new LoggingConfig.LogContext()
                .add("session_id", sessionId)
                .add("thread", Thread.currentThread().getName())
                .build("New bidirectional stream opened");
        logger.info(sessionStartMessage);
        
        return new StreamObserver<Ads.Context>() {
            private int contextCount = 0;
            
            @Override
            public void onNext(Ads.Context context) {
                contextCount++;
                LoggingConfig.Timer contextProcessingTimer = new LoggingConfig.Timer("context_processing");
                
                String contextMessage = new LoggingConfig.LogContext()
                        .add("session_id", sessionId)
                        .add("context_number", contextCount)
                        .add("query", context.getQuery())
                        .add("asin_id", context.getAsinId())
                        .add("understanding_length", context.getUnderstanding().length())
                        .add("understanding_empty", context.getUnderstanding().isEmpty())
                        .add("session_elapsed_ms", sessionTimer.elapsedMs())
                        .build("Received Context message");
                logger.info(contextMessage);
                
                try {
                    if (contextCount == 1) {
                        // Send AdsList version 1 on first Context
                        LoggingConfig.Timer adGenTimer = new LoggingConfig.Timer("ad_generation_v1");
                        Ads.AdsList adsList = adGenerator.generateAds(context, 1);
                        
                        String sendMessage = new LoggingConfig.LogContext()
                                .add("session_id", sessionId)
                                .add("version", 1)
                                .add("ads_count", adsList.getAdsCount())
                                .add("generation_ms", adGenTimer.elapsedMs())
                                .add("context_processing_ms", contextProcessingTimer.elapsedMs())
                                .build("Sending AdsList");
                        logger.info(sendMessage);
                        
                        responseObserver.onNext(adsList);
                        
                    } else if (contextCount == 2) {
                        // Send AdsList version 2 on second Context
                        LoggingConfig.Timer adGenTimer = new LoggingConfig.Timer("ad_generation_v2");
                        Ads.AdsList adsList = adGenerator.generateAds(context, 2);
                        
                        String sendMessage = new LoggingConfig.LogContext()
                                .add("session_id", sessionId)
                                .add("version", 2)
                                .add("ads_count", adsList.getAdsCount())
                                .add("generation_ms", adGenTimer.elapsedMs())
                                .add("context_processing_ms", contextProcessingTimer.elapsedMs())
                                .build("Sending AdsList");
                        logger.info(sendMessage);
                        
                        responseObserver.onNext(adsList);
                        
                        // Schedule version 3 after 50ms delay
                        String scheduleMessage = new LoggingConfig.LogContext()
                                .add("session_id", sessionId)
                                .add("delay_ms", 50)
                                .build("Scheduling delayed version 3 AdsList");
                        logger.info(scheduleMessage);
                        
                        scheduler.schedule(() -> {
                            try {
                                LoggingConfig.Timer finalAdGenTimer = new LoggingConfig.Timer("ad_generation_v3");
                                Ads.AdsList finalAdsList = adGenerator.generateAds(context, 3);
                                
                                String finalSendMessage = new LoggingConfig.LogContext()
                                        .add("session_id", sessionId)
                                        .add("version", 3)
                                        .add("ads_count", finalAdsList.getAdsCount())
                                        .add("generation_ms", finalAdGenTimer.elapsedMs())
                                        .add("session_elapsed_ms", sessionTimer.elapsedMs())
                                        .build("Sending delayed AdsList");
                                logger.info(finalSendMessage);
                                
                                responseObserver.onNext(finalAdsList);
                                
                                // Complete the stream
                                responseObserver.onCompleted();
                                
                                String completionMessage = new LoggingConfig.LogContext()
                                        .add("session_id", sessionId)
                                        .add("total_contexts", contextCount)
                                        .add("total_duration_ms", sessionTimer.elapsedMs())
                                        .build("Stream completed successfully");
                                logger.info(completionMessage);
                                
                            } catch (Exception e) {
                                String errorMessage = new LoggingConfig.LogContext()
                                        .add("session_id", sessionId)
                                        .add("error_type", e.getClass().getSimpleName())
                                        .add("session_elapsed_ms", sessionTimer.elapsedMs())
                                        .build("Error sending version 3");
                                logger.severe(errorMessage + ": " + e.getMessage());
                                responseObserver.onError(e);
                            }
                        }, 50, TimeUnit.MILLISECONDS);
                    }
                } catch (Exception e) {
                    String processingErrorMessage = new LoggingConfig.LogContext()
                            .add("session_id", sessionId)
                            .add("context_number", contextCount)
                            .add("error_type", e.getClass().getSimpleName())
                            .add("processing_ms", contextProcessingTimer.elapsedMs())
                            .build("Error processing Context message");
                    logger.severe(processingErrorMessage + ": " + e.getMessage());
                    responseObserver.onError(e);
                }
            }
            
            @Override
            public void onError(Throwable t) {
                String errorMessage = new LoggingConfig.LogContext()
                        .add("session_id", sessionId)
                        .add("contexts_processed", contextCount)
                        .add("error_type", t.getClass().getSimpleName())
                        .add("session_elapsed_ms", sessionTimer.elapsedMs())
                        .build("Error in bidirectional stream");
                logger.warning(errorMessage + ": " + t.getMessage());
                responseObserver.onError(t);
            }
            
            @Override
            public void onCompleted() {
                String clientCompleteMessage = new LoggingConfig.LogContext()
                        .add("session_id", sessionId)
                        .add("contexts_received", contextCount)
                        .add("session_elapsed_ms", sessionTimer.elapsedMs())
                        .build("Client half-closed stream");
                logger.info(clientCompleteMessage);
                // Client has half-closed the stream, no additional cleanup needed
                // The scheduled version 3 response will complete the server side
            }
        };
    }
    
    /**
     * Shutdown the scheduler to clean up resources
     */
    public void shutdown() {
        scheduler.shutdown();
        try {
            if (!scheduler.awaitTermination(5, TimeUnit.SECONDS)) {
                scheduler.shutdownNow();
            }
        } catch (InterruptedException e) {
            scheduler.shutdownNow();
            Thread.currentThread().interrupt();
        }
    }
}