# Safety Filter File (.sft) for VLC Media Player

A VLC Media Player extension and background playback engine that allows family-safe watching by automatically skipping or muting designated sensitive scenes (such as violence, gore, nudity, or profanity) using standard Safety Filter Files (`.sft`).

---

## ⚡ Quick 1-Click Installation

### macOS & Linux
Open Terminal and run:
```bash
curl -fsSL https://raw.githubusercontent.com/bijuneyyan/vlc/main/install.sh | bash
```
*Or download the repository ZIP and double-click **`Install.command`**.*

---

### Windows
Open PowerShell and run:
```powershell
irm https://raw.githubusercontent.com/bijuneyyan/vlc/main/install.ps1 | iex
```
*Or download the repository ZIP and double-click **`Install.bat`**.*

> **What the installers do**: Automatically install the GUI extension, background engine, and configure VLC preferences (`vlcrc`). No manual settings required!

---

## 🎬 How It Works (Subtitle-Style)

Safety filters work **just like subtitles**:

1. Place `movie.sft` in the same folder as `movie.mp4` (same base name).
2. Open and play the movie in VLC.
3. VLC automatically detects and loads the filter file:
   - **`skip`** segments jump forward past sensitive scenes instantly.
   - **`mute`** segments silence the audio during harsh language and unmute immediately afterwards.
4. If you rename or delete `movie.sft`, filtering turns off automatically.

---

## 🛠️ Creating & Editing Filters in VLC

To create your own `.sft` files while watching a movie:

1. Open VLC Media Player.
2. In the top menu, go to **VLC media player** → **Extensions** → **Safety Filter (.sft)**.
3. Play the video:
   - Click **Set IN = Current Time** at the start of the scene.
   - Click **Set OUT = Current Time** at the end of the scene.
   - Select **Action** (`Skip` or `Mute`) and **Category** (`Gore`, `Violence`, `Nudity`, `Profanity`, etc.).
   - Click **+ ADD FILTER**.
4. Click **Export .sft** to save the filter file (defaults to next to the video or Desktop).
5. Use **Filter Status: `[ Enabled ]` / `[ Disabled ]`** to toggle filtering on or off anytime.

---

## 📄 `.sft` Specification Format

`.sft` files use an open, lightweight JSON format:

```json
{
  "sft_version": "1.0",
  "metadata": {
    "title": "Example Movie",
    "year": 2024,
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

## 🌿 Repository & Branching Workflow

- `main`: Production-ready release branch.
- `develop`: Integration & active development branch.
- `feature/*`: Specific feature branches.

License: MIT
