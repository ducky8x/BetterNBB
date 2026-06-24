# BetterNBB

A macOS overlay for Ninjabrain Bot. Reads Ninjabrain Bot's local API and shows stronghold data in a lightweight always-on-top overlay.

> **This project is archived and no longer maintained. For more updates, check this repository:**
> **(https://github.com/ducky8x/Mac-Speedrunning-Tools**

## Features

- Connects to Ninjabrain Bot through its local API
- Shows stronghold predictions: distance, location, certainty %, Nether coordinates, Nether distance, angle, and turn direction
- Shows eye throw data: boat/status dot, x, z, angle, angle offset, and error
- Color-codes certainty % (green/orange/red) and angle turn difference (green near 0, shifts to red)
- Movement hint based on current position and view direction, dimension-aware (can invalidate RSG runs)
- Shows Ninjabrain Bot info/warning messages in the overlay
- Choose which columns are visible
- Set the number of prediction and eye throw rows
- Drag to place and resize the overlay
- Settings save automatically

## Requirements

- macOS
- Ninjabrain Bot with its API enabled

## Download

### 1. DMG (recommended)

Download the `.dmg` from the Releases page, open it, and drag `BetterNBB.app` to Applications.

> **First launch:** macOS may show a security warning. Go to **System Settings → Privacy & Security → Security** and click **Open Anyway**.

### 2. Direct `.app`

Download `BetterNBB.app` from the release and drag it into Applications.

### 3. Manual source build

Requires Xcode or Apple's Command Line Tools. Download and unzip the source installer, then double-click:

```text
compilinstaller_doubleclicktoinstall.command
```

If the compiler is missing:

```sh
xcode-select --install
```

## Enable the Ninjabrain Bot API

1. Open Ninjabrain Bot and go to its settings.
2. Find and enable the API setting.
3. Keep Ninjabrain Bot running.

BetterNBB expects the API at `http://localhost:52533`. If BetterNBB says it is not connected, the most common cause is that the API setting is off.

## Usage

1. Start Ninjabrain Bot and enable its API.
2. Start BetterNBB.
3. The settings window should show **Connected to Ninjabrain Bot**.
4. Click **Drag to Place Overlay** and drag over the area where you want the overlay.
5. Use the checkboxes to choose which columns and helper rows are visible.

Settings are saved automatically to:

```text
~/Library/Application Support/BetterNBB/config.json
```

## Settings

**Overlay Position** — Use **Drag to Place Overlay** to set where the overlay appears and how large it is.

**Row Counts** — Set the number of prediction rows and eye throw rows.

**Stronghold Columns** — Dist., Location, %, Nether, Nether Dist., Angle

**Eye Throw Columns** — Boat dot, x, z, Angle, Offset, Error

**Options:**
- **Hide 0% predictions** — hides rows with effectively zero certainty
- **Show NBB messages** — shows info/warning messages from Ninjabrain Bot
- **Show movement hint** — shows movement hints relative to player view *(can invalidate RSG runs)*

## Troubleshooting

**Not connected** — Make sure Ninjabrain Bot is running and its API is enabled. Test with:

```sh
curl http://localhost:52533/api/v1/stronghold
```

**Overlay in the wrong place** — Click **Drag to Place Overlay** again.

**Columns too crowded** — Make the overlay wider or disable columns you don't need.

## Changelog

### v1.2.0
- Improved overlay positioning and expanded window customization

### v1.1.0
- Overlay now auto-resizes based on visible rows
- Added DMG and source installer ZIP options

### v1.0.0
- First full release
- API-based overlay replacing OCR
- All core columns, color coding, movement hints, drag placement, and saved settings

## License

Copyright © 2026 ducky8x.

This project is licensed under the GNU GPL v3.0. You're free to use, modify, and distribute this code, but any project that uses it must also be open source and released under the same license. See the [LICENSE](./LICENSE) file for details.
