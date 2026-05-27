# BetterNBB

BetterNBB is a macOS overlay for Ninjabrain Bot. It reads Ninjabrain Bot's local API and shows the stronghold data in a lightweight always-on-top overlay.

## Features

- Connects to Ninjabrain Bot through its local API.
- Shows stronghold predictions:
  - Overworld distance
  - Location
  - Certainty percentage
  - Nether coordinates
  - Nether distance
  - Angle and turn direction
- Shows eye throw data:
  - Boat/status dot
  - x
  - z
  - Angle
  - Angle offset/correction
  - Error
- Color-codes useful values:
  - Certainty percentage turns green/orange/red by confidence.
  - Angle turn difference is green near 0 and shifts toward red as it gets farther away.
  - Boat/status dot follows Ninjabrain Bot-style boat state colors when available.
- Shows a movement hint based on the current player position and view direction.
  - In the Overworld, it shows Overworld blocks first and Nether blocks in parentheses.
  - In the Nether, it shows Nether blocks first and Overworld blocks in parentheses.
  - Disclaimer: This setting can invalidate RSG runs.
- Shows Ninjabrain Bot information/warning messages in the overlay.
- Lets you choose which columns are visible.
- Lets you choose the number of prediction and eye throw rows.
- Lets you drag-select the overlay position and size.
- Saves settings automatically.

## Requirements

- macOS
- Ninjabrain Bot with its API enabled

## Enable The Ninjabrain Bot API

BetterNBB only works if Ninjabrain Bot's local API is enabled.

1. Open Ninjabrain Bot.
2. Open Ninjabrain Bot settings.
3. Find the API setting.
4. Enable the API.
5. Keep Ninjabrain Bot running.

BetterNBB expects Ninjabrain Bot's API at:

```text
http://localhost:52533
```

It uses these API endpoints:

```text
/api/v1/stronghold
/api/v1/stronghold/events
/api/v1/information-messages
/api/v1/information-messages/events
```

If BetterNBB says it is not connected, the most common cause is that the Ninjabrain Bot API setting is off.

Then, move the app to the Applications folder.

## Version 1.0.0

BetterNBB v1.0.0 is the first full release of the API-based overlay.

New in v1.0.0:

- Uses Ninjabrain Bot's local API instead of OCR.
- Live stronghold prediction overlay.
- Configurable stronghold columns:
  - `Dist.`
  - `Location`
  - `%`
  - `Nether`
  - `Nether Dist.`
  - `Angle`
- Configurable eye throw columns:
  - `Boat dot`
  - `x`
  - `z`
  - `Angle`
  - `Offset`
  - `Error`
- Live angle direction display, including left/right turn amount.
- Angle diff color coding from green near 0 to red farther away.
- Nether distance support using Overworld distance divided by 8.
- Movement hint row based on live player position and view direction.
- Dimension-aware movement hints:
  - Overworld players see Overworld blocks first with Nether blocks in parentheses.
  - Nether players see Nether blocks first with Overworld blocks in parentheses.
- Ninjabrain Bot information/warning message display.
- Boat/status dot support.
- Overlay drag placement and resizing.
- Saved settings for overlay position, columns, row counts, and options.

## How To Use

1. Start Ninjabrain Bot.
2. Enable Ninjabrain Bot's API in its settings.
3. Start BetterNBB.
4. The settings window should show `Connected to Ninjabrain Bot`.
5. Click `Drag to Place Overlay`.
6. Drag over the area where you want the overlay to appear.
7. Use the checkboxes to choose which columns and helper rows are visible.

Settings are saved automatically in:

```text
~/Library/Application Support/BetterNBB/config.json
```

## Settings

### Overlay Position

Use `Drag to Place Overlay` to choose where the overlay should appear and how large it should be.

### Row Counts

- `Prediction rows`: number of stronghold prediction rows.
- `Eye throw rows`: number of eye throw rows.

### Stronghold Columns

- `Dist.`
- `Location`
- `%`
- `Nether`
- `Nether Dist.`
- `Angle`

### Eye Throw Columns

- `Boat dot`
- `x`
- `z`
- `Angle`
- `Offset`
- `Error`

### Options

- `Hide 0% predictions`: hides prediction rows with effectively zero certainty.
- `Show NBB messages`: shows information/warning messages from Ninjabrain Bot.
- `Show movement hint (Can invalidate RSG runs)`: shows forward/back and left/right movement hints relative to the player view.

## Troubleshooting

### BetterNBB Says It Is Not Connected

Make sure:

- Ninjabrain Bot is running.
- Ninjabrain Bot's API setting is enabled.
- Nothing is blocking `localhost:52533`.

You can test the API in Terminal:

```sh
curl http://localhost:52533/api/v1/stronghold
```

If that command fails, BetterNBB cannot connect either.

### The Overlay Is In The Wrong Place

Open BetterNBB settings and click `Drag to Place Overlay` again.

### Some Columns Are Too Crowded

Make the overlay wider or disable columns you do not need. BetterNBB scales the text down to fit the visible values, but a very small overlay can still become hard to read.

### Movement Hint Warning

The movement hint is useful for practice or non-RSG contexts, but it can invalidate RSG runs.
