# Troubleshooting Guide for gRPC Bidirectional Streaming

## Overview

This guide provides solutions for common issues encountered when running the gRPC bidirectional streaming playground across Java, C++, and Rust implementations.

## Common Issues and Solutions

### 1. No AdsList Received

**Symptoms:**
- Client logs show "FINAL RESULT: No AdsList received within timeout"
- Client timeout reached without receiving any AdsList messages
- Empty buffer state at timeout

**Possible Causes:**
- Server not running or unreachable
- Network connectivity issues
- Port conflicts
- Server startup failures

**Debugging Steps:**
1. **Check Server Status:**
   ```bash
   # Check if server is listening on the expected port
   netstat -an | grep 8080  # Java server
   netstat -an | grep 50051 # C++/Rust servers
   ```

2. **Verify Server Logs:**
   - Look for "New bidirectional stream opened" messages
   - Check for error messages during startup
   - Verify Context message reception logs

3. **Test Network Connectivity:**
   ```bash
   # Test basic connectivity
   telnet localhost 8080    # Java
   telnet localhost 50051   # C++/Rust
   ```

4. **Check Firewall/Security:**
   - Ensure ports are not blocked by firewall
   - Verify no antivirus interference
   - Check corporate network restrictions

**Solutions:**
- Restart the server with verbose logging: `LOG_LEVEL=DEBUG`
- Use different ports if conflicts exist
- Check server startup logs for dependency issues
- Verify gRPC library versions are compatible

### 2. Version Ordering Problems

**Symptoms:**
- AdsList versions received out of order (e.g., v3 before v2)
- Missing intermediate versions
- Inconsistent version progression

**Possible Causes:**
- Network packet reordering
- Server timing issues
- Clock synchronization problems
- Threading/concurrency issues

**Debugging Steps:**
1. **Enable Debug Logging:**
   ```bash
   LOG_LEVEL=DEBUG ./client
   ```

2. **Check Timing Logs:**
   - Look for "elapsed_ms" values in logs
   - Verify 50ms delays are being respected
   - Check for timing anomalies

3. **Analyze Buffer State:**
   - Review "Buffer state at timeout" debug messages
   - Check "available_versions" arrays
   - Look for version replacement patterns

**Solutions:**
- Increase client timeout if network is slow
- Check system clock synchronization
- Review server threading implementation
- Add network latency compensation

### 3. Performance Degradation

**Symptoms:**
- High latency between messages
- Excessive memory usage
- CPU spikes during operation
- Slow ad generation times

**Possible Causes:**
- Resource constraints (CPU, memory)
- Inefficient algorithms
- Memory leaks
- Excessive logging overhead

**Debugging Steps:**
1. **Monitor Resource Usage:**
   ```bash
   # Monitor during execution
   top -p $(pgrep java)     # Java
   top -p $(pgrep ads_server) # C++
   top -p $(pgrep rust_server) # Rust
   ```

2. **Analyze Performance Logs:**
   - Check "generation_ms" timing
   - Review "total_duration_ms" values
   - Look for "context_processing_ms" spikes

3. **Profile Memory Usage:**
   ```bash
   # Java heap analysis
   jstat -gc $(pgrep java) 1s
   
   # System memory monitoring
   free -m
   ```

**Solutions:**
- Reduce log level to INFO or WARN in production
- Optimize ad generation algorithms
- Implement connection pooling
- Add resource limits and monitoring

### 4. Interoperability Failures

**Symptoms:**
- Client-server combinations fail to communicate
- Protocol buffer serialization errors
- gRPC version mismatches
- Encoding/decoding failures

**Possible Causes:**
- Incompatible protobuf versions
- Different gRPC library versions
- Protocol definition mismatches
- Character encoding issues

**Debugging Steps:**
1. **Verify Protocol Definitions:**
   ```bash
   # Check generated code consistency
   ./scripts/verify-generation.sh
   ```

2. **Test Single-Language Pairs:**
   - Test Java client with Java server first
   - Isolate which language combination fails
   - Compare working vs failing combinations

3. **Check Library Versions:**
   ```bash
   # Java dependencies
   mvn dependency:tree
   
   # C++ library versions
   pkg-config --modversion grpc++
   
   # Rust dependencies
   cargo tree
   ```

**Solutions:**
- Regenerate protobuf code for all languages
- Update to compatible library versions
- Verify proto file syntax and field types
- Test with minimal message content first

### 5. Connection Timeouts and Failures

**Symptoms:**
- "Connection refused" errors
- "Deadline exceeded" messages
- Intermittent connection drops
- SSL/TLS handshake failures

**Possible Causes:**
- Server overload
- Network instability
- Incorrect connection parameters
- Security/certificate issues

**Debugging Steps:**
1. **Check Connection Parameters:**
   - Verify host and port settings
   - Test with localhost vs external IPs
   - Check protocol (HTTP vs HTTPS)

2. **Monitor Network Stability:**
   ```bash
   # Test network stability
   ping -c 100 server_host
   
   # Check packet loss
   mtr server_host
   ```

3. **Analyze gRPC Status Codes:**
   - Look for specific error codes in logs
   - Check gRPC documentation for error meanings
   - Review client retry logic

**Solutions:**
- Implement exponential backoff retry logic
- Increase connection timeouts
- Use connection pooling
- Add health check endpoints

## Debug Mode Configuration

### Environment Variables

Set these environment variables for enhanced debugging:

```bash
# Enable debug logging
export LOG_LEVEL=DEBUG

# Java-specific debugging
export JAVA_OPTS="-Djava.util.logging.config.file=logging.properties"

# C++ debugging
export GRPC_VERBOSITY=DEBUG
export GRPC_TRACE=all

# Rust debugging
export RUST_LOG=debug
export RUST_BACKTRACE=1
```

### Debug Output Examples

**Normal Operation:**
```
2024-01-15T10:30:45.123Z [INFO] [CLIENT] [main] Starting bidirectional stream [query=coffee maker, asin_id=B000123]
2024-01-15T10:30:45.125Z [INFO] [CLIENT] [sender] Sending Context message [context_number=1, understanding_empty=true]
2024-01-15T10:30:45.180Z [INFO] [CLIENT] [receiver] Received AdsList [version=1, ads_count=7, elapsed_ms=55]
2024-01-15T10:30:45.230Z [INFO] [CLIENT] [main] FINAL RESULT: Selected AdsList [version=3, ads_count=8, timeout_ms=105]
```

**Error Condition:**
```
2024-01-15T10:30:45.123Z [INFO] [CLIENT] [main] Starting bidirectional stream [query=coffee maker, asin_id=B000123]
2024-01-15T10:30:45.125Z [ERROR] [CLIENT] [main] GetAds RPC failed [error_code=14, error_message=Connection refused]
2024-01-15T10:30:45.126Z [WARN] [CLIENT] [main] FINAL RESULT: No AdsList received within timeout [timeout_ms=85, buffer_size=0]
```

## Performance Tuning

### Optimal Configuration

**Client Settings:**
- Timeout range: 30-120ms (as per specification)
- Connection timeout: 5 seconds
- Retry attempts: 3 with exponential backoff

**Server Settings:**
- Thread pool size: 2x CPU cores
- Connection limits: 100 concurrent
- Memory limits: 512MB per process

**Network Settings:**
- TCP keep-alive: enabled
- Buffer sizes: 64KB send/receive
- Compression: enabled for large messages

### Monitoring Metrics

Track these key metrics for performance monitoring:

1. **Latency Metrics:**
   - End-to-end request duration
   - Context message send timing
   - AdsList generation time
   - Network round-trip time

2. **Throughput Metrics:**
   - Requests per second
   - Messages per second
   - Bytes transferred per second

3. **Error Metrics:**
   - Connection failure rate
   - Timeout occurrence rate
   - Protocol error frequency

4. **Resource Metrics:**
   - CPU utilization
   - Memory usage
   - Network bandwidth
   - File descriptor usage

## Getting Help

### Log Collection

When reporting issues, collect these logs:

```bash
# Run with debug logging
LOG_LEVEL=DEBUG ./run-server.sh > server.log 2>&1 &
LOG_LEVEL=DEBUG ./run-client.sh > client.log 2>&1

# System information
uname -a > system-info.txt
java -version >> system-info.txt 2>&1
g++ --version >> system-info.txt 2>&1
rustc --version >> system-info.txt 2>&1
```

### Issue Reporting Template

When reporting issues, include:

1. **Environment Information:**
   - Operating system and version
   - Language runtime versions
   - Library versions (gRPC, protobuf)

2. **Problem Description:**
   - Expected behavior
   - Actual behavior
   - Steps to reproduce

3. **Log Files:**
   - Client logs with DEBUG level
   - Server logs with DEBUG level
   - System resource monitoring

4. **Configuration:**
   - Command line arguments used
   - Environment variables set
   - Network configuration

### Contact Information

For additional support:
- Check the project documentation in `docs/`
- Review the interoperability testing guide
- Consult the logging specification for format details