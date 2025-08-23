# Logging Specification for gRPC Bidirectional Streaming

## Overview

This document defines the consistent logging format and debugging support across all implementations (Java, C++, Rust) of the gRPC bidirectional streaming playground.

## Log Format Standard

All implementations should follow this consistent format:

```
[TIMESTAMP] [LEVEL] [COMPONENT] [THREAD/TASK] MESSAGE [CONTEXT]
```

### Components:
- **TIMESTAMP**: ISO 8601 format with milliseconds
- **LEVEL**: DEBUG, INFO, WARN, ERROR
- **COMPONENT**: CLIENT or SERVER
- **THREAD/TASK**: Thread/task identifier for concurrency tracking
- **MESSAGE**: Human-readable message
- **CONTEXT**: Key-value pairs in brackets [key=value, key2=value2]

### Example Log Lines:
```
2024-01-15T10:30:45.123Z [INFO] [CLIENT] [main] Starting bidirectional stream [query=coffee maker, asin_id=B000123]
2024-01-15T10:30:45.125Z [DEBUG] [CLIENT] [sender] Sending Context message [version=1, understanding_empty=true]
2024-01-15T10:30:45.180Z [INFO] [CLIENT] [receiver] Received AdsList [version=1, ads_count=7, elapsed_ms=55]
2024-01-15T10:30:45.230Z [INFO] [CLIENT] [main] Final result selected [version=3, ads_count=8, timeout_ms=105]
```

## Required Log Events

### Client Events:
1. **Stream Start**: Connection establishment with query parameters
2. **Context Send**: Each Context message sent with timing
3. **AdsList Receive**: Each AdsList received with version and timing
4. **Buffer Update**: When AdsList replaces previous version
5. **Timeout Selection**: Random timeout generation and reasoning
6. **Final Result**: Version selection with complete context
7. **Error Handling**: Connection failures, timeouts, parsing errors

### Server Events:
1. **Connection Accept**: New client connection with session ID
2. **Context Receive**: Each Context message with content analysis
3. **AdsList Generate**: Ad generation with algorithm details
4. **AdsList Send**: Each AdsList sent with timing
5. **Stream Complete**: Connection cleanup and statistics
6. **Error Handling**: Processing failures, client disconnections

## Debug Output Requirements

### Message Timing:
- Precise timestamps for all message events
- Elapsed time calculations between related events
- Timeout and delay measurements

### Version Selection Logic:
- Buffer state changes when AdsList messages arrive
- Version comparison and replacement decisions
- Final selection reasoning with available options

### Ad Generation Details:
- Context analysis and scoring factors
- Progressive refinement logic between versions
- Mock data generation parameters

## Performance Metrics

### Client Metrics:
- Total request duration (stream open to final result)
- Time between Context messages (should be ~50ms)
- AdsList reception timing and version progression
- Buffer efficiency (replacements vs new versions)

### Server Metrics:
- Context processing time per message
- Ad generation time per version
- Stream lifecycle duration
- Concurrent connection handling

## Error Categories

### Connection Errors:
- Server unavailable
- Network timeouts
- Authentication failures
- Protocol version mismatches

### Protocol Errors:
- Malformed messages
- Unexpected message sequences
- Version inconsistencies
- Stream state violations

### Processing Errors:
- Ad generation failures
- Context parsing errors
- Buffer management issues
- Resource exhaustion

## Troubleshooting Support

### Common Issues Documentation:
1. **No AdsList Received**: Network, timeout, or server issues
2. **Version Ordering Problems**: Clock skew or processing delays
3. **Performance Degradation**: Resource constraints or inefficient algorithms
4. **Interoperability Failures**: Protocol or serialization mismatches

### Debug Modes:
- **VERBOSE**: All message content and timing details
- **PERFORMANCE**: Timing and resource usage focus
- **PROTOCOL**: Message serialization and stream state tracking
- **ERRORS_ONLY**: Minimal logging for production environments

## Implementation Guidelines

### Java:
- Use `java.util.logging` with custom formatter
- Add structured logging with key-value pairs
- Implement configurable log levels
- Add timing utilities for precise measurements

### C++:
- Replace `std::cout` with structured logging library
- Add thread-safe logging with timestamps
- Implement log level filtering
- Add performance timing utilities

### Rust:
- Enhance existing `tracing` usage with structured fields
- Add consistent event naming and context
- Implement configurable log levels
- Add timing spans for performance tracking

## Configuration

Each implementation should support:
- Log level configuration (DEBUG, INFO, WARN, ERROR)
- Output format selection (structured, human-readable)
- File vs console output options
- Performance metrics enable/disable
- Debug mode selection