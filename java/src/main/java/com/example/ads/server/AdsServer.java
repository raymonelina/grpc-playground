package com.example.ads.server;

import io.grpc.Server;
import io.grpc.ServerBuilder;
import java.io.IOException;
import java.util.concurrent.TimeUnit;
import java.util.logging.Logger;

/**
 * Main server class for the gRPC bidirectional streaming ads service.
 * Handles server lifecycle and provides the AdsService implementation.
 */
public class AdsServer {
    private static final Logger logger = Logger.getLogger(AdsServer.class.getName());
    private static final int DEFAULT_PORT = 50051;
    
    private Server server;
    private final int port;
    private AdsServiceImpl adsService;
    
    public AdsServer(int port) {
        this.port = port;
    }
    
    /**
     * Start the gRPC server
     */
    public void start() throws IOException {
        adsService = new AdsServiceImpl();
        server = ServerBuilder.forPort(port)
                .addService(adsService)
                .build()
                .start();
        
        logger.info("Server started, listening on port " + port);
        
        // Add shutdown hook to gracefully stop the server
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.err.println("*** Shutting down gRPC server since JVM is shutting down");
            try {
                AdsServer.this.stop();
            } catch (InterruptedException e) {
                e.printStackTrace(System.err);
            }
            System.err.println("*** Server shut down");
        }));
    }
    
    /**
     * Stop the gRPC server
     */
    public void stop() throws InterruptedException {
        if (adsService != null) {
            adsService.shutdown();
        }
        if (server != null) {
            server.shutdown().awaitTermination(30, TimeUnit.SECONDS);
        }
    }
    
    /**
     * Block until the server shuts down
     */
    public void blockUntilShutdown() throws InterruptedException {
        if (server != null) {
            server.awaitTermination();
        }
    }
    
    /**
     * Main method to start the server
     */
    public static void main(String[] args) throws IOException, InterruptedException {
        int port = DEFAULT_PORT;
        
        // Parse command line arguments for port
        if (args.length > 0) {
            try {
                port = Integer.parseInt(args[0]);
            } catch (NumberFormatException e) {
                System.err.println("Invalid port number: " + args[0]);
                System.err.println("Usage: java AdsServer [port]");
                System.exit(1);
            }
        }
        
        final AdsServer server = new AdsServer(port);
        server.start();
        server.blockUntilShutdown();
    }
}