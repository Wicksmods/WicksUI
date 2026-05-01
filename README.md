# Wick's UI

> Theme for **ElvUI** — Wick brand palette and L-bracket panel chrome.

Part of the **[Wick suite](https://github.com/Wicksmods/WickSuite)**.

<!-- wick:suite-table:start -->
| Addon | GitHub | CurseForge |
|---|---|---|
| **Wick's TBC BIS Tracker** | [repo](https://github.com/Wicksmods/WickidsTBCBISTracker) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-tbc-bis-tracker) |
| **Wick's CD Tracker** | [repo](https://github.com/Wicksmods/WicksCDTracker) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-cd-tracker) |
| **Wick's Trade Hall** | [repo](https://github.com/Wicksmods/WicksTradeHall) | [CurseForge](https://www.curseforge.com/wow/addons/trade-hall) |
| **Wick's Macro Builder** | [repo](https://github.com/Wicksmods/WicksMacroBuilder) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-macro-builder) |
| **Wick's Combat Log** | [repo](https://github.com/Wicksmods/WicksCombatLog) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-combat-log) |
| **Wick's UI** | [repo](https://github.com/Wicksmods/WicksUI) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-ui) |
<!-- wick:suite-table:end -->

## What it does

Wick's UI is a **plugin for ElvUI** that brings the Wick suite's visual identity to ElvUI's panels:

- **L-bracket chrome** — 10px / 2px fel-green corner brackets on the chat panels, datatext bars, and minimap holder. Same look you get on every other addon in the Wick suite.
- **Wick palette** — opt-in installer writes the locked Wick brand colors into your current ElvUI profile (border, backdrop, accent) and switches the statusbar texture to ElvUI's flat `ElvUI Norm`.

It is **not** a replacement for ElvUI and contains no ElvUI source code. It runs as a registered plugin via `LibElvUIPlugin-1.0`.

## Requirements

- **ElvUI** for TBC Classic — install separately from [tukui.org/elvui](https://tukui.org/elvui).
- TBC Classic Anniversary 2.5.5 (Interface `20505`).

## Install

- **CurseForge:** [curseforge.com/wow/addons/wicks-ui](https://www.curseforge.com/wow/addons/wicks-ui)
- **Manual:** drop the `WicksUI` folder into `World of Warcraft\_anniversary_\Interface\AddOns\`.

ElvUI must be installed first.

## Usage

1. Log in. Brackets auto-apply to ElvUI's chat / datatext / minimap panels.
2. Open `/elvui` → **Plugins** → **Wick's UI**.
3. Click **Apply Wick palette** to write the brand colors and flat statusbar texture into your current ElvUI profile.
4. Confirm the reload prompt.

To revert, click **Revert palette** in the same panel.

## What gets written when you apply the palette

Only four `E.db.general.*` color fields and the active statusbar texture name. Nothing else in your ElvUI profile is touched.

| Field | Wick value |
|---|---|
| `bordercolor` | `#383058` Muted Purple |
| `backdropcolor` | `#0D0A14` Void |
| `backdropfadecolor` | `#0D0A14` Void @ 85% |
| `valuecolor` | `#4FC778` Fel Green |
| Statusbar texture | `ElvUI Norm` (flat) |

## Brand & licensing

Code is MIT (`LICENSE`). The Wick name, logomark, wordmark, and L-bracket visual system are trademarks of Wick and are NOT MIT-licensed — see [`TRADEMARK.md` in the Wick Suite repo](https://github.com/Wicksmods/WickSuite/blob/main/TRADEMARK.md).

Wick's UI is independently authored and is **not affiliated with Tukui-org** or the ElvUI project. ElvUI is the property of its authors. This plugin contains no ElvUI source code, textures, or fonts and consumes only ElvUI's public plugin API at runtime.
