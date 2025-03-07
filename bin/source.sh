#!/bin/bash

# Function to recursively sources all .sh files in the lib directory and its subdirectories.
source_lib_files() {
    local lib_dir="$1"

    if [[ ! -d "$lib_dir" ]]; then
        log_error "Error: lib directory '$lib_dir' not found."
        return 1
    fi

    find "$lib_dir" -type f -name "*.sh" -print0 | while IFS= read -r -d $'\0' file; do
        log_debug "Sourcing: $file"
        source "$file" || {
          log_error "Failed to source: $file"
          return 1 # Fail immediately if a file fails to source
        }
    done

    log_success "All lib files sourced successfully."
}
