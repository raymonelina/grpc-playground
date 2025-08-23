# gRPC Bidirectional Streaming Playground

A multi-language implementation of gRPC bidirectional streaming for ad serving with progressive result refinement.

## Project Structure

```
├── proto/                 # Protocol buffer definitions
│   └── ads.proto         # Core service and message definitions
├── java/                 # Java implementations
│   ├── client/           # Java client implementation
│   └── server/           # Java server implementation
├── cpp/                  # C++ implementations
│   ├── client/           # C++ client implementation
│   └── server/           # C++ server implementation
├── rust/                 # Rust implementations
│   ├── client/           # Rust client implementation
│   └── server/           # Rust server implementation
├── scripts/              # Build and execution scripts
└── docs/                 # Documentation
    ├── logging-specification.md    # Logging format standards
    └── troubleshooting-guide.md   # Common issues and solutions
```

## Protocol

The system implements a bidirectional streaming protocol where:
- Clients send 2 Context messages with a 50ms delay
- Servers respond with 3 AdsList messages (versions 1, 2, 3)
- All implementations are interoperable across languages

## Quick Start

### Build All Implementations
```bash
./scripts/build-all.sh
```

### Run Interoperability Tests
```bash
./scripts/test-interop.sh
```

### Test Logging and Debugging
```bash
./scripts/test-logging.sh
```

## Logging and Debugging

The project includes comprehensive logging and debugging support across all implementations.

### Log Levels
- `ERROR`: Error conditions only
- `WARN`: Warnings and errors
- `INFO`: General information (default)
- `DEBUG`: Detailed debugging information

### Debug Modes
- `NORMAL`: Standard logging (default)
- `VERBOSE`: All debug information
- `PERFORMANCE`: Performance metrics focus
- `PROTOCOL`: Protocol message details
- `ERRORS_ONLY`: Error conditions only

### Configuration
Set environment variables to control logging:

```bash
# Set log level
export LOG_LEVEL=DEBUG

# Set debug mode
export DEBUG_MODE=PERFORMANCE

# Run with enhanced logging
./scripts/run-server.sh java
./scripts/run-client.sh java
```

### Log Format
All implementations follow a consistent format:
```
[TIMESTAMP] [LEVEL] [COMPONENT] [THREAD] MESSAGE [CONTEXT]
```

Example:
```
2024-01-15T10:30:45.123Z [INFO] [CLIENT] [main] Starting bidirectional stream [query=coffee maker, asin_id=B000123]
```

## Testing

### Comprehensive Testing
```bash
# Run all tests including interoperability
./scripts/test-comprehensive.sh

# Test specific language combinations
./scripts/test-interop.sh java cpp

# Test error handling scenarios
./scripts/test-error-handling.sh
```

### Performance Testing
```bash
# Test with performance logging enabled
LOG_LEVEL=DEBUG DEBUG_MODE=PERFORMANCE ./scripts/test-interop.sh
```

## Troubleshooting

For common issues and solutions, see [docs/troubleshooting-guide.md](docs/troubleshooting-guide.md).

### Quick Diagnostics
```bash
# Test logging configuration
./scripts/test-logging.sh --format-only

# Test specific language
./scripts/test-logging.sh --language java

# Test error handling
./scripts/test-logging.sh --error-only
```

## Documentation

- [Logging Specification](docs/logging-specification.md) - Detailed logging format and requirements
- [Troubleshooting Guide](docs/troubleshooting-guide.md) - Common issues and solutions
- [Interoperability Testing](docs/interoperability-testing.md) - Cross-language testing guide

## Getting Started

1. **Build the project:**
   ```bash
   ./scripts/build-all.sh
   ```

2. **Run basic interoperability test:**
   ```bash
   ./scripts/test-interop.sh
   ```

3. **Test logging capabilities:**
   ```bash
   ./scripts/test-logging.sh
   ```

4. **Start development with enhanced debugging:**
   ```bash
   export LOG_LEVEL=DEBUG
   export DEBUG_MODE=VERBOSE
   ./scripts/run-server.sh java &
   ./scripts/run-client.sh java
   ```