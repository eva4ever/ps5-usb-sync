#!/bin/bash

# Script to organize artist directories into batches of 100
# Each batch directory is named "FirstArtist - LastArtist"
#
# Auto-detects mode:
# - Fresh copy: if destination is empty or has no batch folders
# - Sync mode: if destination already has "artist1 - artist2" batch folders
# - Recovery mode: if interrupted previously (temp folder exists)
#
# macOS compatible

set -e

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <source_directory> <destination_directory>"
    echo "Example: $0 /path/to/artists /path/to/organized"
    exit 1
fi

SOURCE_DIR="$1"
DEST_DIR="$2"
BATCH_SIZE=100
FLAT_DIR="$DEST_DIR/.artists_flat_temp"

# Validate source directory
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist"
    exit 1
fi

# Create destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

# --- Detect mode ---
detect_mode() {
    # Check for existing temp folder (interrupted run)
    if [ -d "$FLAT_DIR" ]; then
        echo "recovery"
        return
    fi

    # Check if destination is empty
    if [ -z "$(ls -A "$DEST_DIR" 2>/dev/null)" ]; then
        echo "fresh"
        return
    fi

    # Check for batch folders (pattern: "* - *")
    for item in "$DEST_DIR"/*; do
        if [ -d "$item" ]; then
            item_name=$(basename "$item")
            if [[ "$item_name" == *" - "* ]]; then
                echo "sync"
                return
            fi
        fi
    done

    # Has content but no batch folders - treat as fresh
    echo "fresh"
}

MODE=$(detect_mode)
echo "Detected mode: $MODE"
echo ""

# --- Function to flatten batch folders into temp directory ---
flatten_batches() {
    echo "Flattening existing batch folders..."

    for batch_dir in "$DEST_DIR"/*; do
        if [ -d "$batch_dir" ]; then
            batch_name=$(basename "$batch_dir")
            # Skip hidden directories and non-batch folders
            [[ "$batch_name" == .* ]] && continue

            if [[ "$batch_name" == *" - "* ]]; then
                echo "  Flattening: $batch_name"
                for artist_dir in "$batch_dir"/*; do
                    if [ -d "$artist_dir" ]; then
                        artist_name=$(basename "$artist_dir")
                        # Remove existing if present (avoid duplicates)
                        if [ -d "$FLAT_DIR/$artist_name" ]; then
                            rm -rf "$FLAT_DIR/$artist_name"
                        fi
                        mv "$artist_dir" "$FLAT_DIR/"
                    fi
                done
                # Remove empty batch directory
                rmdir "$batch_dir" 2>/dev/null || rm -rf "$batch_dir"
            fi
        fi
    done

    echo "Flattening complete."
}

# --- Handle different modes ---
if [ "$MODE" == "recovery" ]; then
    echo "=== Recovery mode: Found interrupted session ==="
    echo "Temp folder exists at: $FLAT_DIR"

    # Check if there are any batch folders that need flattening
    HAS_BATCHES=0
    for item in "$DEST_DIR"/*; do
        if [ -d "$item" ]; then
            item_name=$(basename "$item")
            [[ "$item_name" == .* ]] && continue
            if [[ "$item_name" == *" - "* ]]; then
                HAS_BATCHES=1
                break
            fi
        fi
    done

    if [ "$HAS_BATCHES" -eq 1 ]; then
        echo ""
        echo "=== Step 1: Flattening remaining batch folders ==="
        flatten_batches
    fi

    echo ""
    echo "=== Step 2: Syncing with rsync ==="
    echo "Syncing from '$SOURCE_DIR' to '$FLAT_DIR'..."
    rsync -a --info=progress2 "$SOURCE_DIR"/ "$FLAT_DIR"/
    echo "Sync complete."
    echo ""

    echo "=== Step 3: Re-organizing into batch folders ==="
    WORK_DIR="$FLAT_DIR"

elif [ "$MODE" == "sync" ]; then
    echo "=== Sync mode ==="

    echo "=== Step 1: Flattening existing batch folders ==="
    mkdir -p "$FLAT_DIR"
    flatten_batches
    echo ""

    echo "=== Step 2: Syncing with rsync ==="
    echo "Syncing from '$SOURCE_DIR' to '$FLAT_DIR'..."
    rsync -a --info=progress2 "$SOURCE_DIR"/ "$FLAT_DIR"/
    echo "Sync complete."
    echo ""

    echo "=== Step 3: Re-organizing into batch folders ==="
    WORK_DIR="$FLAT_DIR"

else
    echo "=== Fresh copy mode ==="
    echo ""
    WORK_DIR="$SOURCE_DIR"
fi

# --- Get sorted list of artist directories ---
ARTISTS=()
while IFS= read -r dir; do
    [ -n "$dir" ] && ARTISTS+=("$dir")
done < <(ls -1 "$WORK_DIR" | while read -r name; do
    # Skip hidden files/folders
    [[ "$name" == .* ]] && continue
    if [ -d "$WORK_DIR/$name" ]; then
        echo "$name"
    fi
done | sort -f -u)

TOTAL_ARTISTS=${#ARTISTS[@]}

if [ "$TOTAL_ARTISTS" -eq 0 ]; then
    echo "No artist directories found"
    [ -d "$FLAT_DIR" ] && rmdir "$FLAT_DIR" 2>/dev/null || true
    exit 1
fi

echo "Found $TOTAL_ARTISTS artist directories"

# Calculate number of batches needed
NUM_BATCHES=$(( (TOTAL_ARTISTS + BATCH_SIZE - 1) / BATCH_SIZE ))

if [ "$NUM_BATCHES" -gt 100 ]; then
    echo "Warning: More than 100 batches needed ($NUM_BATCHES). Only processing first 10000 artists."
    NUM_BATCHES=100
fi

echo "Creating $NUM_BATCHES batch directories..."
echo ""

# Process each batch
for ((batch=0; batch<NUM_BATCHES; batch++)); do
    START_INDEX=$((batch * BATCH_SIZE))
    END_INDEX=$((START_INDEX + BATCH_SIZE - 1))

    if [ "$END_INDEX" -ge "$TOTAL_ARTISTS" ]; then
        END_INDEX=$((TOTAL_ARTISTS - 1))
    fi

    FIRST_ARTIST="${ARTISTS[$START_INDEX]}"
    LAST_ARTIST="${ARTISTS[$END_INDEX]}"

    BATCH_DIR_NAME="${FIRST_ARTIST} - ${LAST_ARTIST}"
    BATCH_DIR="$DEST_DIR/$BATCH_DIR_NAME"

    echo "Batch $((batch + 1))/$NUM_BATCHES: '$BATCH_DIR_NAME'"
    mkdir -p "$BATCH_DIR"

    for ((i=START_INDEX; i<=END_INDEX; i++)); do
        ARTIST="${ARTISTS[$i]}"

        # Skip if artist directory doesn't exist (already moved or duplicate)
        if [ ! -d "$WORK_DIR/$ARTIST" ]; then
            echo "  Skipping (not found): $ARTIST"
            continue
        fi

        if [ "$MODE" == "fresh" ]; then
            # Copy from source
            cp -R "$WORK_DIR/$ARTIST" "$BATCH_DIR/"
        else
            # Move from temp flat directory
            mv "$WORK_DIR/$ARTIST" "$BATCH_DIR/"
        fi
    done
done

# Clean up temp directory if it exists and is empty
if [ -d "$FLAT_DIR" ]; then
    REMAINING=$(ls -A "$FLAT_DIR" 2>/dev/null | wc -l)
    if [ "$REMAINING" -eq 0 ]; then
        rmdir "$FLAT_DIR"
        echo ""
        echo "Cleaned up temp directory."
    else
        echo ""
        echo "Warning: $REMAINING items remain in temp folder (duplicates or special names):"
        ls "$FLAT_DIR"
        echo ""
        echo "You may want to manually review: $FLAT_DIR"
    fi
fi

echo ""
echo "=== Done! ==="
echo "Organized $TOTAL_ARTISTS artists into $NUM_BATCHES directories at '$DEST_DIR'"
