package com.example.ads.client;

import ads.Ads;
import ads.AdsServiceGrpc;
import com.example.ads.common.LoggingConfig;
import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.grpc.stub.StreamObserver;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadLocalRandom;
import java.util.logging.Logger;
import java.util.logging.Level;

/**
 * gRPC bidirectional streaming client for the ads service.
 * Implements the client-side logic for progressive ad refinement.
 */
public class AdsClient {
    private static final Logger logger = LoggingConfig.configureLogger(AdsClient.class, "CLIENT");
    
    private final ManagedChannel channel;
    private final AdsServiceGrpc.AdsServiceStub asyncStub;
    
    // Configuration constants
    private static final int CONTEXT_DELAY_MS = 50;
    private static final int MIN_TIMEOUT_MS = 30;
    private static final int MAX_TIMEOUT_MS = 120;
    
    /**
     * Construct client connecting to the ads server at {@code host:port}.
     */
    public AdsClient(String host, int port) {
        this(ManagedChannelBuilder.forAddress(host, port)
                .usePlaintext()
                .build());
    }
    
    /**
     * Construct client for accessing ads server using the existing channel.
     */
    AdsClient(ManagedChannel channel) {
        this.channel = channel;
        this.asyncStub = AdsServiceGrpc.newStub(channel);
    }
    
    /**
     * Get ads using bidirectional streaming with progressive context refinement.
     * 
     * @param query The search query
     * @param asinId The product identifier
     * @param understanding The refined understanding (will be sent in second context)
     * @return The final AdsList or null if no ads received
     */
    public Ads.AdsList getAds(String query, String asinId, String understanding) {
        LoggingConfig.Timer overallTimer = new LoggingConfig.Timer("bidirectional_stream");
        
        String startMessage = new LoggingConfig.LogContext()
            .add("query", query)
            .add("asin_id", asinId)
            .add("understanding_provided", !understanding.isEmpty())
            .build("Starting bidirectional stream");
        logger.info(startMessage);
        
        // Thread-safe map to store received AdsList by version
        final ConcurrentHashMap<Integer, Ads.AdsList> adsBuffer = new ConcurrentHashMap<>();
        final CountDownLatch finishedLatch = new CountDownLatch(1);
        
        // Response observer to handle incoming AdsList messages
        StreamObserver<Ads.AdsList> responseObserver = new StreamObserver<Ads.AdsList>() {
            @Override
            public void onNext(Ads.AdsList adsList) {
                long elapsedMs = overallTimer.elapsedMs();
                int version = (int) adsList.getVersion();
                boolean isReplacement = adsBuffer.containsKey(version);
                
                String receiveMessage = new LoggingConfig.LogContext()
                    .add("version", version)
                    .add("ads_count", adsList.getAdsCount())
                    .add("elapsed_ms", elapsedMs)
                    .add("is_replacement", isReplacement)
                    .build("Received AdsList");
                logger.info(receiveMessage);
                
                // Log debug details about the ads if debug level is enabled
                if (logger.isLoggable(Level.FINE)) {
                    for (int i = 0; i < adsList.getAdsCount(); i++) {
                        Ads.Ad ad = adsList.getAds(i);
                        String adMessage = new LoggingConfig.LogContext()
                            .add("version", version)
                            .add("ad_index", i)
                            .add("asin_id", ad.getAsinId())
                            .add("ad_id", ad.getAdId())
                            .add("score", String.format("%.3f", ad.getScore()))
                            .build("Ad details");
                        logger.fine(adMessage);
                    }
                }
                
                // Buffer the AdsList, replacing any previous version
                Ads.AdsList previousVersion = adsBuffer.put(version, adsList);
                if (previousVersion != null) {
                    String replaceMessage = new LoggingConfig.LogContext()
                        .add("version", version)
                        .add("old_ads_count", previousVersion.getAdsCount())
                        .add("new_ads_count", adsList.getAdsCount())
                        .build("Replaced AdsList in buffer");
                    logger.fine(replaceMessage);
                }
            }
            
            @Override
            public void onError(Throwable t) {
                String errorMessage = new LoggingConfig.LogContext()
                    .add("error_type", t.getClass().getSimpleName())
                    .add("error_message", t.getMessage())
                    .add("elapsed_ms", overallTimer.elapsedMs())
                    .build("GetAds RPC failed");
                logger.log(Level.WARNING, errorMessage, t);
                finishedLatch.countDown();
            }
            
            @Override
            public void onCompleted() {
                String completeMessage = new LoggingConfig.LogContext()
                    .add("elapsed_ms", overallTimer.elapsedMs())
                    .add("versions_received", adsBuffer.size())
                    .build("Server completed response stream");
                logger.info(completeMessage);
                finishedLatch.countDown();
            }
        };
        
        // Start the bidirectional stream
        StreamObserver<Ads.Context> requestObserver = asyncStub.getAds(responseObserver);
        
        try {
            // Send first Context message with empty understanding
            LoggingConfig.Timer contextTimer = new LoggingConfig.Timer("first_context_send");
            Ads.Context firstContext = Ads.Context.newBuilder()
                    .setQuery(query)
                    .setAsinId(asinId)
                    .setUnderstanding("")
                    .build();
            
            String firstContextMessage = new LoggingConfig.LogContext()
                    .add("context_number", 1)
                    .add("understanding_empty", true)
                    .add("elapsed_ms", overallTimer.elapsedMs())
                    .build("Sending Context message");
            logger.info(firstContextMessage);
            requestObserver.onNext(firstContext);
            
            // Wait 50ms before sending second context
            logger.fine("Waiting " + CONTEXT_DELAY_MS + "ms before second Context message");
            Thread.sleep(CONTEXT_DELAY_MS);
            
            // Send second Context message with filled understanding
            Ads.Context secondContext = Ads.Context.newBuilder()
                    .setQuery(query)
                    .setAsinId(asinId)
                    .setUnderstanding(understanding)
                    .build();
            
            String secondContextMessage = new LoggingConfig.LogContext()
                    .add("context_number", 2)
                    .add("understanding_length", understanding.length())
                    .add("elapsed_ms", overallTimer.elapsedMs())
                    .build("Sending Context message");
            logger.info(secondContextMessage);
            requestObserver.onNext(secondContext);
            
            // Half-close the client side of the stream
            requestObserver.onCompleted();
            String halfCloseMessage = new LoggingConfig.LogContext()
                    .add("elapsed_ms", overallTimer.elapsedMs())
                    .build("Half-closed client stream");
            logger.info(halfCloseMessage);
            
            // Generate random timeout between 30-120ms
            int timeoutMs = ThreadLocalRandom.current().nextInt(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS + 1);
            String timeoutMessage = new LoggingConfig.LogContext()
                    .add("timeout_ms", timeoutMs)
                    .add("min_timeout", MIN_TIMEOUT_MS)
                    .add("max_timeout", MAX_TIMEOUT_MS)
                    .build("Generated random timeout for result selection");
            logger.info(timeoutMessage);
            
            // Wait for the random timeout
            Thread.sleep(timeoutMs);
            
            // Return the most recent AdsList (highest version number)
            Ads.AdsList finalResult = null;
            int maxVersion = 0;
            
            // Log buffer state for debugging
            String bufferStateMessage = new LoggingConfig.LogContext()
                    .add("buffer_size", adsBuffer.size())
                    .add("available_versions", adsBuffer.keySet().toString())
                    .add("elapsed_ms", overallTimer.elapsedMs())
                    .build("Buffer state at timeout");
            logger.fine(bufferStateMessage);
            
            for (Ads.AdsList adsList : adsBuffer.values()) {
                if (adsList.getVersion() > maxVersion) {
                    maxVersion = (int) adsList.getVersion();
                    finalResult = adsList;
                }
            }
            
            if (finalResult != null) {
                String finalResultMessage = new LoggingConfig.LogContext()
                        .add("selected_version", finalResult.getVersion())
                        .add("ads_count", finalResult.getAdsCount())
                        .add("total_duration_ms", overallTimer.elapsedMs())
                        .add("versions_considered", adsBuffer.size())
                        .build("FINAL RESULT: Selected AdsList");
                logger.info(finalResultMessage);
                
                // Log performance summary
                String perfMessage = new LoggingConfig.LogContext()
                        .add("operation", "bidirectional_stream")
                        .add("total_duration_ms", overallTimer.elapsedMs())
                        .add("timeout_used_ms", timeoutMs)
                        .add("versions_received", adsBuffer.size())
                        .add("final_version", finalResult.getVersion())
                        .build("Performance summary");
                logger.info(perfMessage);
            } else {
                String noResultMessage = new LoggingConfig.LogContext()
                        .add("total_duration_ms", overallTimer.elapsedMs())
                        .add("timeout_ms", timeoutMs)
                        .add("buffer_size", adsBuffer.size())
                        .build("FINAL RESULT: No AdsList received within timeout");
                logger.warning(noResultMessage);
            }
            
            return finalResult;
            
        } catch (InterruptedException e) {
            String interruptMessage = new LoggingConfig.LogContext()
                    .add("elapsed_ms", overallTimer.elapsedMs())
                    .add("buffer_size", adsBuffer.size())
                    .build("Client interrupted");
            logger.log(Level.WARNING, interruptMessage, e);
            Thread.currentThread().interrupt();
            return null;
        } catch (RuntimeException e) {
            String runtimeErrorMessage = new LoggingConfig.LogContext()
                    .add("error_type", e.getClass().getSimpleName())
                    .add("elapsed_ms", overallTimer.elapsedMs())
                    .build("Runtime error during stream processing");
            logger.log(Level.SEVERE, runtimeErrorMessage, e);
            // Cancel RPC
            requestObserver.onError(e);
            throw e;
        }
    }
    
    /**
     * Shutdown the client channel.
     */
    public void shutdown() throws InterruptedException {
        channel.shutdown().awaitTermination(5, TimeUnit.SECONDS);
    }
    
    /**
     * Main method to run the client.
     */
    public static void main(String[] args) throws Exception {
        String host = "localhost";
        int port = 8080;
        
        // Parse command line arguments if provided
        if (args.length >= 2) {
            host = args[0];
            port = Integer.parseInt(args[1]);
        }
        
        AdsClient client = new AdsClient(host, port);
        try {
            // Example usage
            String query = "coffee maker";
            String asinId = "B000123456";
            String understanding = "user wants high-quality coffee brewing equipment";
            
            Ads.AdsList result = client.getAds(query, asinId, understanding);
            
            if (result != null) {
                System.out.println(String.format("Final result: AdsList version %d with %d ads", 
                    result.getVersion(), result.getAdsCount()));
                
                for (Ads.Ad ad : result.getAdsList()) {
                    System.out.println(String.format("  Ad: asinId=%s, adId=%s, score=%.3f", 
                        ad.getAsinId(), ad.getAdId(), ad.getScore()));
                }
            } else {
                System.out.println("No ads received");
            }
            
        } finally {
            client.shutdown();
        }
    }
}