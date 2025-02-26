#!/bin/bash

# Define source directory containing torrents and destination directory
SOURCE_DIR="$1"
DEST_DIR="$2"

# Ensure both arguments are provided
if [[ -z "$SOURCE_DIR" || -z "$DEST_DIR" ]]; then
    echo "Usage: $0 <source-directory> <destination-directory>"
    exit 1
fi

# Ensure source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory does not exist."
    exit 1
fi

# Ensure destination directory exists
mkdir -p "$DEST_DIR"

# Find all .torrent files in the source directory
TORRENT_FILES=("$SOURCE_DIR"/*.torrent)

# Check if any torrents are found
if [[ ! -e "${TORRENT_FILES[0]}" ]]; then
    echo "No torrent files found in $SOURCE_DIR"
    exit 0
fi

# Start downloading each torrent
for TORRENT_FILE in "${TORRENT_FILES[@]}"; do
    echo "Starting download for: $TORRENT_FILE"
    aria2c --dir="$DEST_DIR" --seed-time=0 --follow-torrent=mem --max-concurrent-downloads=5 \
           --bt-max-peers=50 --bt-tracker-connect-timeout=10 --bt-tracker-timeout=10 \
           --bt-tracker-interval=60 "$TORRENT_FILE"
done

echo "All downloads completed."
exit 0
