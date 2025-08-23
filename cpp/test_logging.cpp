#include "common/logging.h"
#include <cstdint>
#include <thread>

int main() {
    logging::Logger logger("TEST");
    
    // Test different types that might cause ambiguity
    uint32_t version = 123;
    size_t buffer_size = 456;
    int timeout = 789;
    long elapsed = 1000;
    bool flag = true;
    double score = 0.85;
    std::thread::id thread_id = std::this_thread::get_id();
    
    std::string test_message = logging::LogContext()
        .add("version", version)
        .add("buffer_size", buffer_size)
        .add("timeout", timeout)
        .add("elapsed", elapsed)
        .add("flag", flag)
        .add("score", score)
        .add("thread_id", thread_id)
        .build("Test message with various types");
    
    logger.info(test_message);
    
    return 0;
}