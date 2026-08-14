# ZRYX

Standalone Luau payload for the Roblox experience Violence District. It uses a native Roblox UI and does not load a mutable UI library from a remote branch.

## Features

- Survivor finish-line automation for known Violence District maps
- Low-population server hopping with temporary failed-server blacklist
- Optional Discord webhook reporting with stat deltas
- Optional auto-execution after teleport through `queue_on_teleport`
- Local persistence for toggles, server range, script URL, snapshots, and ignored servers
- Webhook URLs are intentionally kept only in memory and are not written to disk

## Usage

Run `zryx.lua` from a Roblox client executor while inside Violence District (`PlaceId` `93978595733734`). Open or hide the panel with `RightShift`.

For Auto Execute, enable the toggle. Its default payload URL is `https://raw.githubusercontent.com/zaerrruwww/zryx/refs/heads/main/zryx.lua`; the script queues it immediately before teleporting. It will not teleport when Auto Execute is enabled but the URL or executor capability is missing.

## Notes

- The script validates the active place and exits outside Violence District.
- Finish completion is confirmed from a role or map-state transition. A position update alone is not reported as a completed round.
- Roblox game updates can change maps, roles, remotes, or anti-cheat behavior. Update the known-map adapters only after testing in an authorized environment.
- Automation may violate the game's Terms of Service and can put an account at risk.

## Attribution

This is an independent implementation informed by the public feature set of [Rzor731/VD-AUTO-FARM](https://github.com/Rzor731/VD-AUTO-FARM), which is MIT licensed. No source files from that repository are included here.
# zryx
