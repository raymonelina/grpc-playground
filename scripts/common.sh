#!/bin/bash

# Common utilities for gRPC playground scripts
# Source this file in other scripts: source "$(dirname "$0")/common.sh"

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    case "$color" in
        "green") echo -e "\033[32m✅ $message\033[0m" ;;
        "red") echo -e "\033[31m❌ $message\033[0m" ;;
        "yellow") echo -e "\033[33m⚠️  $message\033[0m" ;;
        "blue") echo -e "\033[36mℹ️  $message\033[0m" ;;
        *) echo "$message" ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}