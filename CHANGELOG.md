# Changelog

All notable changes to **Wick's UI** are documented here.

## [0.2.1] — 2026-04-30

### Fixed
- Brackets now anchor to ElvUI's `.backdrop` child frame when present, so they sit at the corners of the visible skinned art instead of the outer Blizzard frame's invisible padding. Affects character pane, spellbook, quest log, and most other Blizzard panels.

## [0.2.0] — 2026-04-30

### Fixed
- Minimap holder bracket — corrected frame name from `MMHolder` to `ElvUI_MinimapHolder`.

### Added
- Brackets on Blizzard panels — character, paperdoll, reputation, honor, quest log/give, merchant, bank, mail, gossip, taxi, trade, loot, friends, world map, spellbook, talent, tabard, tradeskill, craft, auction, inspect, macro, key binding. Decorated on first show; idempotent across re-opens.
- TBC 2.5.5 API compatibility — `IsAddOnLoaded` and `GetAddOnMetadata` now read from `C_AddOns` namespace with legacy fallback.
- `/wui` slash command — load-time diagnostic prints addon load state, library availability, init/hook/registration status, and any captured errors.
- AceAddon-based plugin pattern (`E.Libs.EP:HookInitialize`) for reliable plugin registration in `/elvui` → Plugins.

## [0.1.0] — 2026-04-30

Initial release.

### Added
- ElvUI plugin registration via `LibElvUIPlugin-1.0`. Appears under `/elvui → Plugins → Wick's UI`.
- **L-bracket chrome:** 10px / 2px fel-green corner brackets auto-applied to ElvUI's chat panels, datatext panels, and minimap holder. Configurable arm length and thickness in the options pane.
- **Wick palette installer:** opt-in "Apply Wick palette" button writes the locked Wick brand colors (Fel `#4FC778`, Void `#0D0A14`, Muted Purple `#383058`, Off-White `#D4C8A1`) into the current ElvUI profile, plus the flat `ElvUI Norm` statusbar texture. Revert button restores ElvUI defaults.
- **Saved variables** (`WicksUIDB`) per account.

### Notes
- Compatible with TBC Classic Anniversary 2.5.5 (Interface 20505).
- Requires **ElvUI** — install separately from https://tukui.org/elvui.
- Theme application writes to your active ElvUI profile. Switch profiles before applying if you want to keep your old settings.
