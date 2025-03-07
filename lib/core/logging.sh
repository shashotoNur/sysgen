#!/bin/bash

# --- Logging Functions ---

log_info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$1" >&2; }
log_warning() { printf "\033[1;33m[WARNING]\033[0m %s\n" "$1" >&2; }
log_error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1" >&2; }
log_success() { printf "\033[1;32m[SUCCESS]\033[0m %s\n" "$1" >&2; }
log_debug() { printf "\e[90mDEBUG:\e[0m %s\n" "$1" >&2; }
