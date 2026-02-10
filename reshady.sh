#!/usr/bin/env bash
set -euo pipefail

# reshady: interactive ReShade helper for Steam / Steam Deck
# Features:
#   - Detect Steam libraries and installed games
#   - Install or update ReShade via reshade-linux.sh
#   - Apply bundled presets (e.g., PSX CRT) and set launch options
#   - Non-destructive uninstall (backs up ReShade files)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESET_DIR="${SCRIPT_DIR}/presets"

APPID_OVERRIDE=""   # allow manual override via flag later
declare -A GAME_API_MAP=(
  [377840]=d3d9        # FINAL FANTASY IX
  [377160]=d3d9        # FINAL FANTASY VIII Remastered
  [39140]=d3d9         # FINAL FANTASY VII (2013)
  [39150]=d3d9         # FINAL FANTASY VIII (2013)
  [582010]=dxgi        # Monster Hunter: World
  [1172380]=dxgi       # Elden Ring
  [1245620]=dxgi       # Cyberpunk 2077
)
STEAM_BASE=""
USERDATA_ID=""

title() { echo -e "\n=== $* ==="; }
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
reshady - interactive ReShade helper for Steam/Steam Deck
Run without arguments for interactive menu.

Options:
  --help                     Show this help.
  list-games                 Print "appid|name|path" for installed games.
  install  --appid ID --game-path PATH --api API --preset FILE
  preset   --game-path PATH --preset FILE          (apply preset only)
  toggle   --appid ID --game-path PATH             (rename dll / launch option)
  remove   --game-path PATH                        (backup + remove ReShade files)

Interactive actions (menu):
  Install/Update ReShade   - Detect game, suggest API, install ReShade, apply preset, set launch option.
  Apply preset only        - Swap preset without re-installing.
  Remove ReShade (backup)  - Move ReShade files into timestamped backup.
  Add custom preset        - Copy a user .ini into presets/ so it appears in the chooser.
  Toggle ReShade on/off    - Rename injected DLL and add/remove launch option (non-destructive).

Notes:
  - Uses WINEDLLOVERRIDES="d3dcompiler_47=n;d3d9=n,b" %command%
  - Suggests API for common games; otherwise prompts.
  - Respects libraryfolders.vdf to find multiple libraries.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

pick() {
  # args: list items, returns selection
  local items=("$@")
  if command -v fzf >/dev/null 2>&1; then
    printf '%s\n' "${items[@]}" | fzf --prompt="Select> "
  else
    local i sel
    for i in "${!items[@]}"; do printf "%2d) %s\n" $((i+1)) "${items[$i]}"; done
    read -rp "Choice: " sel
    [[ "$sel" =~ ^[0-9]+$ ]] || die "Invalid selection"
    ((sel>=1 && sel<=${#items[@]})) || die "Out of range"
    echo "${items[$((sel-1))]}"
  fi
}

detect_steam_base() {
  local candidates=(
    "${HOME}/.local/share/Steam"
    "${HOME}/.steam/steam"
    "${HOME}/snap/steam/common/.local/share/Steam"
  )
  for p in "${candidates[@]}"; do
    [[ -d "$p/steamapps" ]] && { STEAM_BASE="$p"; return; }
  done
  die "Could not find Steam installation (checked ${candidates[*]})."
}

detect_userdata() {
  local path
  path="$(find "${STEAM_BASE}/userdata" -maxdepth 1 -mindepth 1 -type d | head -n1)"
  [[ -n "$path" ]] || die "No userdata folder found."
  USERDATA_ID="$(basename "$path")"
}

parse_libraryfolders() {
  local vdf="${STEAM_BASE}/steamapps/libraryfolders.vdf"
  [[ -f "$vdf" ]] || die "libraryfolders.vdf not found at $vdf"
  python3 - <<'PY'
import json, re, sys, pathlib
vdf = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8', errors='ignore')
tokens = re.findall(r'"[^"]*"|\{|\}', vdf)
def parse(i=0):
    obj={}
    while i<len(tokens):
        t=tokens[i]
        if t=='}': return obj,i+1
        key=t.strip('"')
        if tokens[i+1]=='{':
            val,i=parse(i+2)
            obj[key]=val
        else:
            obj[key]=tokens[i+1].strip('"')
            i+=2
            continue
        i+=1
    return obj,i
root,_=parse()
libs=root.get('libraryfolders',{})
for k,v in libs.items():
    if not isinstance(v,dict): continue
    p=v.get('path')
    if p: print(p)
PY "$vdf"
}

list_games() {
  local libs=("$@")
  python3 - "$STEAM_BASE" "${libs[@]}" <<'PY'
import pathlib, re, sys
steam_base = pathlib.Path(sys.argv[1])
libs = [pathlib.Path(p) for p in sys.argv[2:]]
games=[]
def parse_acf(path):
    txt=path.read_text(encoding='utf-8', errors='ignore')
    tokens=re.findall(r'"[^"]*"|\{|\}', txt)
    def parse(i=0):
        obj={}
        while i<len(tokens):
            t=tokens[i]
            if t=='}': return obj,i+1
            key=t.strip('"')
            if tokens[i+1]=='{':
                val,i=parse(i+2)
                obj[key]=val
            else:
                obj[key]=tokens[i+1].strip('"')
                i+=2
                continue
            i+=1
        return obj,i
    root,_=parse()
    return root.get('AppState',{})

for lib in libs:
    acf_dir=lib/"steamapps"
    if not acf_dir.exists(): continue
    for acf in acf_dir.glob("appmanifest_*.acf"):
        data=parse_acf(acf)
        appid=data.get("appid")
        name=data.get("name")
        inst=data.get("installdir")
        if not (appid and name and inst): continue
        game_path=acf_dir/"common"/inst
        if game_path.exists():
            games.append((name,appid,str(game_path)))

games.sort(key=lambda x:x[0].lower())
for name,appid,path in games:
    print(f"{appid}|{name}|{path}")
PY
}

ensure_reshade_script() {
  local dest="${SCRIPT_DIR}/reshade-linux.sh"
  if [[ ! -f "$dest" ]]; then
    title "Downloading reshade-linux.sh"
    curl -L -o "$dest" https://github.com/kevinlekiller/reshade-steam-proton/raw/main/reshade-linux.sh
    chmod +x "$dest"
  fi
  echo "$dest"
}

install_reshade() {
  local game_path="$1" api="$2"
  local script
  script="$(ensure_reshade_script)"
  title "Installing ReShade to $game_path with API $api"
  printf 'i\n%s\ny\nn\n%s\ny\n' "$game_path" "$api" | "$script"
}

suggest_api() {
  local appid="$1"
  if [[ -n "${GAME_API_MAP[$appid]:-}" ]]; then
    echo "${GAME_API_MAP[$appid]}"
  else
    pick d3d9 dxgi opengl32 d3d8
  fi
}

copy_crt_top() {
  local merged="$1"
  [[ -d "$merged" ]] || return 0
  if [[ -f "${merged}/SweetFX/CRT.fx" ]]; then
    cp "${merged}/SweetFX/CRT.fx" "${merged}/CRT_PSX.fx"
  elif [[ -f "${merged}/CRT.fx" ]]; then
    cp "${merged}/CRT.fx" "${merged}/CRT_PSX.fx"
  fi
}

apply_preset() {
  local game_path="$1" preset_file="$2"
  local resh_ini="${game_path}/ReShade.ini"
  local preset_name
  preset_name="$(basename "$preset_file")"
  cp "$preset_file" "${game_path}/${preset_name}"
  if [[ -f "$resh_ini" ]]; then
    python3 - <<PY
from configparser import ConfigParser
import pathlib
ini=pathlib.Path("${resh_ini}")
p=ConfigParser()
p.read(ini, encoding="utf-8")
if "GENERAL" not in p: p["GENERAL"]={}
p["GENERAL"]["PresetPath"]= ".\\${preset_name}"
p["GENERAL"]["StartupPresetPath"]= ".\\${preset_name}"
ini.write_text("\n".join(["[%s]\n%s"%(s,"\n".join(f"{k}={v}" for k,v in p[s].items())) for s in p.sections()]), encoding="utf-8")
PY
  fi
}

set_launch_option() {
  local appid="$1" value="$2"
  local vdf="${STEAM_BASE}/userdata/${USERDATA_ID}/config/localconfig.vdf"
  [[ -f "$vdf" ]] || die "localconfig.vdf not found at $vdf"
  python3 - <<PY
import pathlib,re,sys
vdf_path=pathlib.Path("${vdf}")
text=vdf_path.read_text(encoding="utf-8", errors="ignore")
tok=re.findall(r'"[^"\\\\]*(?:\\\\.[^"\\\\]*)*"|\\{|\\}', text)
def parse(i=0):
    obj={}
    while i<len(tok):
        t=tok[i]
        if t=='}': return obj,i+1
        key=t.strip('"')
        if tok[i+1]=='{':
            val,i=parse(i+2)
            obj[key]=val
        else:
            obj[key]=tok[i+1].strip('"')
            i+=2
            continue
        i+=1
    return obj,i
root,_=parse()
apps=root.setdefault("UserLocalConfigStore",{}).setdefault("Software",{}).setdefault("Valve",{}).setdefault("Steam",{}).setdefault("apps",{})
apps.setdefault("${appid}",{})["LaunchOptions"]="${value}"
def ser(obj,indent=0):
    tab="\t"*indent
    lines=[]
    for k,v in obj.items():
        if isinstance(v,dict):
            lines.append(f'{tab}"{k}"\n{tab}{{\n' + "\n".join(ser(v,indent+1)) + f'\n{tab}}}')
        else:
            lines.append(f'{tab}"{k}"\t\t"{v}"')
    return lines
out="\n".join(ser(root))+"\n"
vdf_path.write_text(out, encoding="utf-8")
PY
}

clear_launch_option() {
  local appid="$1"
  local vdf="${STEAM_BASE}/userdata/${USERDATA_ID}/config/localconfig.vdf"
  [[ -f "$vdf" ]] || return 0
  python3 - <<PY
import pathlib,re,sys
vdf_path=pathlib.Path("${vdf}")
text=vdf_path.read_text(encoding="utf-8", errors="ignore")
tok=re.findall(r'"[^"\\\\]*(?:\\\\.[^"\\\\]*)*"|\\{|\\}', text)
def parse(i=0):
    obj={}
    while i<len(tok):
        t=tok[i]
        if t=='}': return obj,i+1
        key=t.strip('"')
        if tok[i+1]=='{':
            val,i=parse(i+2)
            obj[key]=val
        else:
            obj[key]=tok[i+1].strip('"')
            i+=2
            continue
        i+=1
    return obj,i
root,_=parse()
apps=root.setdefault("UserLocalConfigStore",{}).setdefault("Software",{}).setdefault("Valve",{}).setdefault("Steam",{}).setdefault("apps",{})
if "${appid}" in apps and "LaunchOptions" in apps["${appid}"]:
    del apps["${appid}"]["LaunchOptions"]
def ser(obj,indent=0):
    tab="\t"*indent
    lines=[]
    for k,v in obj.items():
        if isinstance(v,dict):
            lines.append(f'{tab}"{k}"\n{tab}{{\n' + "\n".join(ser(v,indent+1)) + f'\n{tab}}}')
        else:
            lines.append(f'{tab}"{k}"\t\t"{v}"')
    return lines
out="\n".join(ser(root))+"\n"
vdf_path.write_text(out, encoding="utf-8")
PY
}

backup_and_remove() {
  local game_path="$1"
  local stamp
  stamp="$(date +%Y%m%d_%H%M%S)"
  local backup="${game_path}/reshady_backup_${stamp}"
  mkdir -p "$backup"
  for f in ReShade.ini ReShade_shaders d3d9.dll dxgi.dll d3dcompiler_47.dll opengl32.dll; do
    if [[ -e "${game_path}/${f}" ]]; then
      mv "${game_path}/${f}" "$backup/"
    fi
  done
  echo "Backed up ReShade files to $backup"
}

choose_game() {
  local libs=("$@")
  local games
  IFS=$'\n' read -r -d '' -a games < <(list_games "${libs[@]}" && printf '\0')
  [[ ${#games[@]} -gt 0 ]] || die "No installed games found."
  local choice
  choice="$(pick "${games[@]}")"
  APPID="${choice%%|*}"
  local rest="${choice#*|}"
  GAME_NAME="${rest%%|*}"
  GAME_PATH="${rest##*|}"
}

choose_preset() {
  local presets
  IFS=$'\n' read -r -d '' -a presets < <(cd "$PRESET_DIR" && ls *.ini && printf '\0')
  [[ ${#presets[@]} -gt 0 ]] || die "No presets found in ${PRESET_DIR}"
  local p
  p="$(pick "${presets[@]}")"
  echo "${PRESET_DIR}/${p}"
}

main_menu() {
  PS3="Select an action: "
  select action in "Install/Update ReShade" "Apply preset only" "Remove ReShade (backup)" "Add custom preset" "Toggle ReShade on/off" "Quit"; do
    case "$REPLY" in
      1) do_install; break;;
      2) do_preset_only; break;;
      3) do_remove; break;;
      4) add_custom_preset; break;;
      5) toggle_reshade; break;;
      6) exit 0;;
      *) echo "Invalid";;
    esac
  done
}

do_install() {
  local libs
  IFS=$'\n' read -r -d '' -a libs < <(parse_libraryfolders && printf '\0')
  choose_game "${libs[@]}"
  title "Selected: ${GAME_NAME} (${APPID})"
  local api_choice
  api_choice="$(suggest_api "$APPID")"
  install_reshade "$GAME_PATH" "$api_choice"
  copy_crt_top "${GAME_PATH}/ReShade_shaders/Merged/Shaders"
  local preset_file
  preset_file="$(choose_preset)"
  apply_preset "$GAME_PATH" "$preset_file"
  set_launch_option "$APPID" 'WINEDLLOVERRIDES="d3dcompiler_47=n;d3d9=n,b" %command%'
  echo "Done. Restart Steam then launch the game."
}

do_preset_only() {
  local libs
  IFS=$'\n' read -r -d '' -a libs < <(parse_libraryfolders && printf '\0')
  choose_game "${libs[@]}"
  local preset_file
  preset_file="$(choose_preset)"
  copy_crt_top "${GAME_PATH}/ReShade_shaders/Merged/Shaders"
  apply_preset "$GAME_PATH" "$preset_file"
  echo "Preset applied to ${GAME_NAME}. Reload in-game (Home -> Reload)."
}

do_remove() {
  local libs
  IFS=$'\n' read -r -d '' -a libs < <(parse_libraryfolders && printf '\0')
  choose_game "${libs[@]}"
  backup_and_remove "$GAME_PATH"
}

add_custom_preset() {
  read -rp "Path to preset (.ini) to add: " src
  [[ -f "$src" ]] || die "File not found: $src"
  local base
  base="$(basename "$src")"
  cp "$src" "${PRESET_DIR}/${base}"
  echo "Added preset ${base} to ${PRESET_DIR}"
}

toggle_reshade() {
  local libs
  IFS=$'\n' read -r -d '' -a libs < <(parse_libraryfolders && printf '\0')
  choose_game "${libs[@]}"
  local dir="$GAME_PATH"
  local dlls=(d3d9 dxgi opengl32 d3d8)
  local toggled=0
  for d in "${dlls[@]}"; do
    if [[ -f "${dir}/${d}.dll" ]]; then
      mv "${dir}/${d}.dll" "${dir}/${d}.reshady.off"
      clear_launch_option "$APPID"
      echo "Disabled ReShade (renamed ${d}.dll -> ${d}.reshady.off) for ${GAME_NAME}"
      toggled=1
      break
    elif [[ -f "${dir}/${d}.reshady.off" ]]; then
      mv "${dir}/${d}.reshady.off" "${dir}/${d}.dll"
      set_launch_option "$APPID" 'WINEDLLOVERRIDES="d3dcompiler_47=n;d3d9=n,b" %command%'
      echo "Enabled ReShade (restored ${d}.dll) for ${GAME_NAME}"
      toggled=1
      break
    fi
  done
  [[ $toggled -eq 1 ]] || echo "No ReShade override DLL found to toggle in ${dir}"
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "list-games" ]]; then
  require_cmd curl
  require_cmd python3
  detect_steam_base
  detect_userdata
  mapfile -t libs < <(parse_libraryfolders)
  list_games "${libs[@]}"
  exit 0
fi

if [[ "${1:-}" == "install" ]]; then
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --appid) APPID="$2"; shift 2;;
      --game-path) GAME_PATH="$2"; shift 2;;
      --api) API="$2"; shift 2;;
      --preset) PRESET="$2"; shift 2;;
      *) echo "Unknown arg $1"; exit 1;;
    esac
  done
  [[ -n "${APPID:-}" && -n "${GAME_PATH:-}" && -n "${API:-}" && -n "${PRESET:-}" ]] || die "Missing args for install"
  require_cmd curl; require_cmd python3
  detect_steam_base; detect_userdata
  install_reshade "$GAME_PATH" "$API"
  copy_crt_top "${GAME_PATH}/ReShade_shaders/Merged/Shaders"
  apply_preset "$GAME_PATH" "$PRESET"
  set_launch_option "$APPID" 'WINEDLLOVERRIDES="d3dcompiler_47=n;d3d9=n,b" %command%'
  exit 0
fi

if [[ "${1:-}" == "preset" ]]; then
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --game-path) GAME_PATH="$2"; shift 2;;
      --preset) PRESET="$2"; shift 2;;
      *) echo "Unknown arg $1"; exit 1;;
    esac
  done
  [[ -n "${GAME_PATH:-}" && -n "${PRESET:-}" ]] || die "Missing args for preset"
  copy_crt_top "${GAME_PATH}/ReShade_shaders/Merged/Shaders"
  apply_preset "$GAME_PATH" "$PRESET"
  exit 0
fi

if [[ "${1:-}" == "toggle" ]]; then
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --appid) APPID="$2"; shift 2;;
      --game-path) GAME_PATH="$2"; shift 2;;
      *) echo "Unknown arg $1"; exit 1;;
    esac
  done
  [[ -n "${APPID:-}" && -n "${GAME_PATH:-}" ]] || die "Missing args for toggle"
  GAME_NAME="(cli)"
  toggle_reshade_cli=1
  dir="$GAME_PATH"
  dlls=(d3d9 dxgi opengl32 d3d8)
  toggled=0
  for d in "${dlls[@]}"; do
    if [[ -f "${dir}/${d}.dll" ]]; then
      mv "${dir}/${d}.dll" "${dir}/${d}.reshady.off"
      clear_launch_option "$APPID"
      echo "Disabled ReShade (renamed ${d}.dll -> ${d}.reshady.off)"
      toggled=1
      break
    elif [[ -f "${dir}/${d}.reshady.off" ]]; then
      mv "${dir}/${d}.reshady.off" "${dir}/${d}.dll"
      set_launch_option "$APPID" 'WINEDLLOVERRIDES="d3dcompiler_47=n;d3d9=n,b" %command%'
      echo "Enabled ReShade (restored ${d}.dll)"
      toggled=1
      break
    fi
  done
  [[ $toggled -eq 1 ]] || echo "No ReShade override DLL found to toggle in ${dir}"
  exit 0
fi

if [[ "${1:-}" == "remove" ]]; then
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --game-path) GAME_PATH="$2"; shift 2;;
      *) echo "Unknown arg $1"; exit 1;;
    esac
  done
  [[ -n "${GAME_PATH:-}" ]] || die "Missing game-path for remove"
  backup_and_remove "$GAME_PATH"
  exit 0
fi

require_cmd curl
require_cmd python3

detect_steam_base
detect_userdata
main_menu
