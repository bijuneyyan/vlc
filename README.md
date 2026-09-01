# Safety Filter File (.sft) for VLC Media Player

A VLC Media Player feature and extension that allows family-safe watching by automatically skipping or muting designated sensitive scenes (such as violence, gore, nudity, or profanity) using standard Safety Filter Files (`.sft`).

## Features
- **Auto-Play Filter**: Load a `.sft` file corresponding to a movie/video to automatically skip or mute sensitive timestamps during playback.
- **In-Out Marker Editor**: Interactive GUI inside VLC to easily mark `IN` and `OUT` timestamps while watching a movie, assign categories & actions, and generate/export `.sft` files.
- **Supported Actions**:
  - `skip`: Instantly skips the designated segment.
  - `mute`: Mutes the audio for the designated segment and unmutes afterwards.

---

## Installation

To install the `.sft` Safety Filter extension in VLC:

### macOS
Copy `lua/extensions/sft_filter.lua` to:
`~/Library/Application Support/org.videolan.vlc/lua/extensions/`
*(Create the `lua/extensions` directory if it does not exist)*

### Windows
Copy `lua/extensions/sft_filter.lua` to:
`%APPDATA%\vlc\lua\extensions\`

### Linux
Copy `lua/extensions/sft_filter.lua` to:
`~/.local/share/vlc/lua/extensions/`

---

## Usage

1. Open VLC Media Player.
2. Go to **View** -> **Safety Filter (.sft)**.
3. Use the dialog to:
   - **Load `.sft`**: Load an existing `.sft` file to apply filter rules.
   - **Mark IN / OUT**: Capture timestamps live during video playback.
   - **Add Filter Segment**: Save designated segments with `skip` or `mute` action.
   - **Export .sft**: Generate and save the `.sft` metadata file.

---

## `.sft` File Format Specification

`.sft` files use a lightweight JSON structure:

```json
{
  "sft_version": "1.0",
  "metadata": {
    "title": "Example Movie",
    "year": 2024,
    "duration_seconds": 7200,
    "created_by": "VLC User"
  },
  "filters": [
    {
      "id": 1,
      "start_time": 120.5,
      "end_time": 135.0,
      "action": "skip",
      "category": "gore",
      "description": "Graphic scene skip"
    },
    {
      "id": 2,
      "start_time": 450.0,
      "end_time": 458.2,
      "action": "mute",
      "category": "profanity",
      "description": "Mute harsh language"
    }
  ]
}
```

---

## Repository & Development Setup

This project uses Git with the following branch workflow:
- `main`: Stable, release-ready versions.
- `develop`: Integration branch for active development.
- `feature/*`: Specific feature branches.

License: MIT
