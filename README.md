# PS5 USB Sync

Organizes artist directories into batches of 100, with each batch folder named after the first and last artist alphabetically (e.g., `Another Channel - Billain`).

## Usage

First, make the script executable:
```bash
chmod +x organize_artists.sh
```

Then run:
```bash
./organize_artists.sh <source_directory> <destination_directory>
```

### Example

```bash
./organize_artists.sh /Volumes/Music/FLAC "/Volumes/Extreme SSD/Music"
```

## Modes

The script auto-detects which mode to use:

| Mode | Condition | Action |
|------|-----------|--------|
| Fresh | Destination is empty | Copies all artists into batch folders |
| Sync | Destination has batch folders | Flattens, rsyncs from source, reorganizes |
| Recovery | `.artists_flat_temp` exists | Resumes interrupted session |

## Features

- Organizes up to 10,000 artists (100 batches × 100 artists)
- Case-insensitive alphabetical sorting
- Handles duplicates and special characters
- Recovers from interruptions (Ctrl+C safe)
- Uses rsync for efficient syncing

## Output Structure

```
destination/
├── Another Channel - Billain/
│   ├── Another Channel/
│   ├── Al Wootton/
│   ├── Alex Coulton/
│   └── ... (up to 100 artists)
├── Bing - Cloaka/
│   └── ...
├── Tim Reaper - Versa/
│   └── ...
└── ...
```

## Requirements

- macOS or Linux with Bash
- rsync

### Installing rsync on macOS

rsync comes pre-installed on macOS, but it's an older version. To install the latest version:

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install rsync
brew install rsync
```

To verify installation:
```bash
rsync --version
```
