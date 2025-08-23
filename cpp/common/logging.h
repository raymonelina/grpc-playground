#pragma once

#include <iostream>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <string>
#include <map>
#include <thread>

/**
 * Structured logging utilities for consistent formatting across C++ implementations.
 * Implements the logging specification defined in docs/logging-specification.md
 */
namespace logging {

enum class Level {
    DEBUG,
    INFO,
    WARN,
    ERROR
};

class LogContext {
private:
    std::map<std::string, std::string> context_;

public:
    LogContext& add(const std::string& key, const std::string& value) {
        context_[key] = value;
        return *this;
    }
    
    LogContext& add(const std::string& key, int value) {
        context_[key] = std::to_string(value);
        return *this;
    }
    
    LogContext& add(const std::string& key, long value) {
        context_[key] = std::to_string(value);
        return *this;
    }
    
    LogContext& add(const std::string& key, double value) {
        std::ostringstream oss;
        oss << std::fixed << std::setprecision(3) << value;
        context_[key] = oss.str();
        return *this;
    }
    
    LogContext& add(const std::string& key, bool value) {
        context_[key] = value ? "true" : "false";
        return *this;
    }
    
    std::string build(const std::string& message) const {
        if (context_.empty()) {
            return message;
        }
        
        std::ostringstream oss;
        oss << message << " [";
        bool first = true;
        for (const auto& pair : context_) {
            if (!first) oss << ", ";
            oss << pair.first << "=" << pair.second;
            first = false;
        }
        oss << "]";
        return oss.str();
    }
};

class Timer {
private:
    std::chrono::steady_clock::time_point start_time_;
    std::string operation_;

public:
    Timer(const std::string& operation) 
        : start_time_(std::chrono::steady_clock::now()), operation_(operation) {}
    
    long elapsed_ms() const {
        auto now = std::chrono::steady_clock::now();
        return std::chrono::duration_cast<std::chrono::milliseconds>(now - start_time_).count();
    }
    
    std::string get_timing_context() const {
        return "operation=" + operation_ + ", elapsed_ms=" + std::to_string(elapsed_ms());
    }
};

class DebugMode {
public:
    static bool is_verbose() {
        const char* debug_mode = std::getenv("DEBUG_MODE");
        return debug_mode && std::string(debug_mode) == "VERBOSE";
    }
    
    static bool is_performance() {
        const char* debug_mode = std::getenv("DEBUG_MODE");
        return debug_mode && std::string(debug_mode) == "PERFORMANCE";
    }
    
    static bool is_protocol() {
        const char* debug_mode = std::getenv("DEBUG_MODE");
        return debug_mode && std::string(debug_mode) == "PROTOCOL";
    }
    
    static bool is_errors_only() {
        const char* debug_mode = std::getenv("DEBUG_MODE");
        return debug_mode && std::string(debug_mode) == "ERRORS_ONLY";
    }
    
    static std::string get_current_mode() {
        const char* debug_mode = std::getenv("DEBUG_MODE");
        return debug_mode ? std::string(debug_mode) : "NORMAL";
    }
};

class Logger {
private:
    std::string component_;
    Level min_level_;
    
    std::string get_timestamp() const {
        auto now = std::chrono::system_clock::now();
        auto time_t = std::chrono::system_clock::to_time_t(now);
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            now.time_since_epoch()) % 1000;
        
        std::ostringstream oss;
        oss << std::put_time(std::gmtime(&time_t), "%Y-%m-%dT%H:%M:%S");
        oss << '.' << std::setfill('0') << std::setw(3) << ms.count() << 'Z';
        return oss.str();
    }
    
    std::string level_to_string(Level level) const {
        switch (level) {
            case Level::DEBUG: return "DEBUG";
            case Level::INFO: return "INFO";
            case Level::WARN: return "WARN";
            case Level::ERROR: return "ERROR";
            default: return "UNKNOWN";
        }
    }
    
    std::string get_thread_id() const {
        std::ostringstream oss;
        oss << std::this_thread::get_id();
        return oss.str();
    }

public:
    Logger(const std::string& component) : component_(component) {
        // Set log level from environment variable or default to INFO
        const char* log_level_env = std::getenv("LOG_LEVEL");
        std::string log_level = log_level_env ? log_level_env : "INFO";
        
        if (log_level == "DEBUG") min_level_ = Level::DEBUG;
        else if (log_level == "INFO") min_level_ = Level::INFO;
        else if (log_level == "WARN") min_level_ = Level::WARN;
        else if (log_level == "ERROR") min_level_ = Level::ERROR;
        else min_level_ = Level::INFO;
        
        // Adjust level based on debug mode
        if (DebugMode::is_errors_only()) {
            min_level_ = Level::ERROR;
        } else if (DebugMode::is_verbose()) {
            min_level_ = Level::DEBUG;
        }
        
        // Log configuration info
        info("Logger configured [component=" + component + ", level=" + log_level + 
             ", debug_mode=" + DebugMode::get_current_mode() + "]");
    }
    
    void log(Level level, const std::string& message) {
        if (level < min_level_) return;
        
        // Filter based on debug mode
        if (DebugMode::is_performance() && level == Level::DEBUG) {
            // Only show performance-related debug messages
            if (message.find("elapsed_ms") == std::string::npos && 
                message.find("generation_ms") == std::string::npos &&
                message.find("duration_ms") == std::string::npos) {
                return;
            }
        }
        
        std::cout << get_timestamp() << " [" << level_to_string(level) << "] "
                  << "[" << component_ << "] [" << get_thread_id() << "] "
                  << message << std::endl;
    }
    
    void debug(const std::string& message) { log(Level::DEBUG, message); }
    void info(const std::string& message) { log(Level::INFO, message); }
    void warn(const std::string& message) { log(Level::WARN, message); }
    void error(const std::string& message) { log(Level::ERROR, message); }
    
    bool is_debug_enabled() const { return min_level_ <= Level::DEBUG; }
};

} // namespace logging