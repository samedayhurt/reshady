reshady
========

Interactive ReShade helper for Steam / Steam Deck. Installs ReShade, applies bundled presets, and safely removes/backs it up.

Features
- Detects Steam libraries and installed games (Deck paths supported).
- Installs/updates ReShade via `reshade-linux.sh` (downloaded automatically).
- Applies bundled presets (PSX CRT, Clean Bloom, Performance Sharp).
- Sets Steam launch options for Proton: `WINEDLLOVERRIDES="d3dcompiler_47=n;d3d9=n,b" %command%`.
- Non-destructive uninstall backs up ReShade files.

Requirements
- Bash, curl, python3, 7z, git, wine (all present on SteamOS/Deck).
- Optional: `fzf` for nicer selection; falls back to numbered menus.

Install
```bash
git clone https://github.com/yourname/reshady.git
cd reshady
chmod +x reshady.sh
```

Usage
```bash
./reshady.sh
```
CLI (for automation / Decky backend)
```bash
./reshady.sh list-games
./reshady.sh install --appid 377840 --game-path "/path/to/game/x64" --api d3d9 --preset presets/psx_crt.ini
./reshady.sh preset  --game-path "/path/to/game/x64" --preset presets/clean_bloom.ini
./reshady.sh toggle  --appid 377840 --game-path "/path/to/game/x64"
./reshady.sh remove  --game-path "/path/to/game/x64"
```

Install guide: desktop / Deck (script)
1) Clone this repo on the Deck (desktop mode) or any Linux box with Steam installed.
2) Run `./reshady.sh` and pick “Install/Update ReShade”.
3) Choose the game, accept the suggested API (or pick one), choose a preset.
4) Restart Steam, launch the game, press Home to open ReShade.

Install guide: Decky plugin (clean route)
- The script already exposes non-interactive CLI calls (`list-games`, `install`, `preset`, `toggle`, `remove`). A Decky backend can shell out to these.
- Frontend: list games via `list-games`, then call `install`/`toggle`/`preset` as the user clicks buttons.
- Bundle `presets/` with the plugin; expose an “Add custom preset” file picker that copies .ini into that folder and calls `preset`.
CLI (for automation / Decky backend)
```bash
./reshady.sh list-games
./reshady.sh install --appid 377840 --game-path "/path/to/game/x64" --api d3d9 --preset presets/psx_crt.ini
./reshady.sh preset  --game-path "/path/to/game/x64" --preset presets/clean_bloom.ini
./reshady.sh toggle  --appid 377840 --game-path "/path/to/game/x64"
./reshady.sh remove  --game-path "/path/to/game/x64"
```
Main menu options:
1) Install/Update ReShade – choose a game; script suggests an API from a known list (else prompts), then pick a preset.
2) Apply preset only – reuses existing ReShade install and just swaps the preset.
3) Remove ReShade (backup) – moves ReShade files to `reshady_backup_<timestamp>` inside the game folder.
4) Add custom preset – copies any .ini you point to into `presets/` so it appears in the chooser.
5) Toggle ReShade on/off – renames the injected DLL and adds/removes the launch option (non-destructive, keeps presets intact).

Bundled presets
- `psx_crt.ini` – CRT scanlines/curvature + light film grain + mild bloom (needs `CRT_PSX.fx` copied automatically).
- `clean_bloom.ini` – subtle HDR bloom + clarity.
- `perf_sharp.ini` – lightweight sharpening only.

Notes
- The script copies `CRT.fx` to `CRT_PSX.fx` in the merged shader folder so the CRT preset shows up.
- Steam launch options are written to `userdata/<id>/config/localconfig.vdf`. Restart Steam after running.
- For non-default Steam library locations, the script reads `libraryfolders.vdf` automatically.
- API suggestions: map covers FFIX/FF7/FF8 (d3d9), Monster Hunter: World / Elden Ring / Cyberpunk (dxgi). Others will prompt you to choose (d3d9, dxgi, opengl32, or d3d8).
- Toggle is non-destructive: it just renames the override DLL (d3d9/dxgi/opengl32/d3d8) to `.reshady.off` and removes/restores the launch option.
- Adding presets: drop any ReShade preset .ini into `presets/` or use “Add custom preset”. Sources: reshade.me forums, NexusMods ReShade section, or your own exported `.ini`. Ensure required shaders exist; this tool installs the standard packs from `reshade-linux.sh` only.

Uninstall manually (if ever needed)
- Delete/move `ReShade.ini`, `ReShade_shaders/`, and override dll (`d3d9.dll` or `dxgi.dll`) from the game directory, or use menu option 3 which backs them up.
