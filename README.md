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

Decky plugin integration (recommended flow)
- Backend: call the existing CLI commands (`list-games`, `install`, `preset`, `toggle`, `remove`). No extra binaries needed; the script auto-downloads `reshade-linux.sh` if missing and handles ReShade installation.
- Frontend wire-up:
  - On load, call `./reshady.sh list-games` to populate games (format: `appid|name|path`).
  - “Install/Update” button -> `install --appid <id> --game-path <path> --api <d3d9|dxgi|opengl32|d3d8> --preset <ini>`.
  - “Apply preset” button -> `preset --game-path <path> --preset <ini>`.
  - “Toggle” button -> `toggle --appid <id> --game-path <path>` (non-destructive rename + launch option change).
  - “Remove” button -> `remove --game-path <path>` (backs up files).
- Ship the `presets/` folder with the plugin; add a file picker that copies a user .ini into `presets/` then calls `preset` so it shows up in-game.
- Decky backend tip: run commands with `cwd` set to the plugin directory so relative `presets/` paths resolve.
- Restart Steam after install/toggle because launch options are written to `userdata/<id>/config/localconfig.vdf`.

Decky plugin in this repo
- The repo now includes a Decky plugin (backend + prebuilt frontend in `dist/index.js`) that shells out to `reshady.sh` and `presets/`.
- Build is optional because `dist/index.js` is already present. If you want to rebuild: `npm install && npm run build` (Node 18+), then copy `dist/` back; otherwise skip.
- Install to Decky: copy/symlink the repo into `~/homebrew/plugins/Reshady`, or zip the contents and drop into Decky Loader. Ensure `reshady.sh` remains executable (`chmod +x reshady.sh`); the backend runs it with cwd set to the plugin dir so `presets/` resolve.
- The plugin backend exposes `list_games`, `install`, `apply_preset`, `toggle`, `remove`; the frontend provides buttons for each and preset/API selectors.

Decky quickstart (no build needed)
1) `git clone https://github.com/samedayhurt/reshady.git && cd reshady`
2) `chmod +x reshady.sh`
3) `mkdir -p ~/homebrew/plugins/Reshady && cp -r . ~/homebrew/plugins/Reshady`
4) Restart Decky Loader; the “Reshady” tab should appear with game picker, preset/API selectors, and Install/Toggle/Remove buttons.
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
