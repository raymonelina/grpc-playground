package com.example.ads.common;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.logging.Formatter;
import java.util.logging.Handler;
import java.util.logging.Level;
import java.util.logging.LogRecord;
import java.util.logging.Logger;
import java.util.logging.ConsoleHandler;

/**
 * Centralized logging configuration for consistent formatting across all components.
 * Implements the logging specification defined in docs/logging-specification.md
 */
public class LoggingConfig {
    
    private static final DateTimeFormatter TIMESTAMP_FORMATTER = 
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC);
    
    /**
     * Custom formatter that implements the standard log format:
     * [TIMESTAMP] [LEVEL] [COMPONENT] [THREAD] MESSAGE [CONTEXT]
     */
    public static class StructuredFormatter extends Formatter {
        private final String component;
        
        public StructuredFormatter(String component) {
            this.component = component;
        }
        
        @Override
        public String format(LogRecord record) {
            String timestamp = TIMESTAMP_FORMATTER.format(Instant.ofEpochMilli(record.getMillis()));
            String level = record.getLevel().getName();
            String thread = Thread.currentThread().getName();
            String message = record.getMessage();
            
            // Extract context from message if it contains key-value pairs
            String context = "";
            if (message.contains("[") && message.contains("]")) {
                int contextStart = message.lastIndexOf("[");
                if (contextStart > 0) {
                    context = " " + message.substring(contextStart);
                    message = message.substring(0, contextStart).trim();
                }
            }
            
            return String.format("%s [%s] [%s] [%s] %s%s%n", 
                timestamp, level, component, thread, message, context);
        }
    }
    
    /**
     * Configure a logger with structured formatting for the specified component.
     */
    public static Logger configureLogger(Class<?> clazz, String component) {
        Logger logger = Logger.getLogger(clazz.getName());
        
        // Remove default handlers to avoid duplicate output
        Handler[] handlers = logger.getHandlers();
        for (Handler handler : handlers) {
            logger.removeHandler(handler);
        }
        
        // Add console handler with structured formatter
        ConsoleHandler consoleHandler = new ConsoleHandler();
        consoleHandler.setFormatter(new StructuredFormatter(component));
        consoleHandler.setLevel(Level.ALL);
        logger.addHandler(consoleHandler);
        
        // Set log level based on environment variable or default to INFO
        String logLevel = System.getProperty("LOG_LEVEL", "INFO");
        logger.setLevel(Level.parse(logLevel));
        logger.setUseParentHandlers(false);
        
        // Log configuration info
        logger.info("Logger configured [component=" + component + ", level=" + logLevel + "]");
        
        return logger;
    }
    
    /**
     * Debug mode configuration based on environment variables.
     */
    public static class DebugMode {
        public static final boolean VERBOSE = "VERBOSE".equals(System.getProperty("DEBUG_MODE", ""));
        public static final boolean PERFORMANCE = "PERFORMANCE".equals(System.getProperty("DEBUG_MODE", ""));
        public static final boolean PROTOCOL = "PROTOCOL".equals(System.getProperty("DEBUG_MODE", ""));
        public static final boolean ERRORS_ONLY = "ERRORS_ONLY".equals(System.getProperty("DEBUG_MODE", ""));
        
        public static boolean isEnabled(String mode) {
            return mode.equals(System.getProperty("DEBUG_MODE", ""));
        }
        
        public static String getCurrentMode() {
            return System.getProperty("DEBUG_MODE", "NORMAL");
        }
    }
    
    /**
     * Utility class for creating structured log messages with context.
     */
    public static class LogContext {
        private final StringBuilder context = new StringBuilder();
        
        public LogContext add(String key, Object value) {
            if (context.length() > 0) {
                context.append(", ");
            }
            context.append(key).append("=").append(value);
            return this;
        }
        
        public String build(String message) {
            if (context.length() > 0) {
                return message + " [" + context.toString() + "]";
            }
            return message;
        }
    }
    
    /**
     * Performance timing utility for measuring operation durations.
     */
    public static class Timer {
        private final long startTime;
        private final String operation;
        
        public Timer(String operation) {
            this.operation = operation;
            this.startTime = System.currentTimeMillis();
        }
        
        public long elapsedMs() {
            return System.currentTimeMillis() - startTime;
        }
        
        public String getTimingContext() {
            return "operation=" + operation + ", elapsed_ms=" + elapsedMs();
        }
    }
}