import asyncio
import os
import subprocess
from pathlib import Path

from decky_plugin import logger

PLUGIN_DIR = Path(__file__).resolve().parent.parent
SCRIPT_PATH = PLUGIN_DIR / "reshady.sh"


def _ensure_executable():
    if SCRIPT_PATH.exists():
        SCRIPT_PATH.chmod(SCRIPT_PATH.stat().st_mode | 0o111)


def _run(cmd: list[str]) -> dict:
    """Run a command, return dict with stdout/stderr/exit."""
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(PLUGIN_DIR),
            capture_output=True,
            text=True,
            check=False,
        )
        return {
            "code": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
        }
    except Exception as exc:  # pragma: no cover - defensive for decky runtime
        logger.error(f"Command failed: {cmd}: {exc}")
        return {"code": -1, "stdout": "", "stderr": str(exc)}


def _split_games(stdout: str) -> list[dict]:
    games = []
    for line in stdout.strip().splitlines():
        if "|" not in line:
            continue
        appid, name, path = line.split("|", 2)
        games.append({"appid": appid, "name": name, "path": path})
    return games


class Plugin:
    async def _main(self):
        logger.info("Reshady backend starting")
        _ensure_executable()

    async def _unload(self):
        logger.info("Reshady backend unloaded")

    # Exposed methods callable from frontend -------------------------------
    async def list_games(self):
        if not SCRIPT_PATH.exists():
            return {"error": "reshady.sh not found", "games": []}
        res = await asyncio.to_thread(_run, [str(SCRIPT_PATH), "list-games"])
        games = _split_games(res.get("stdout", ""))
        return {"games": games, "code": res["code"], "stderr": res["stderr"]}

    async def install(
        self, appid: str, game_path: str, api: str, preset: str
    ):
        if not SCRIPT_PATH.exists():
            return {"error": "reshady.sh not found"}
        cmd = [
            str(SCRIPT_PATH),
            "install",
            "--appid",
            appid,
            "--game-path",
            game_path,
            "--api",
            api,
            "--preset",
            preset,
        ]
        return await asyncio.to_thread(_run, cmd)

    async def apply_preset(self, game_path: str, preset: str):
        cmd = [str(SCRIPT_PATH), "preset", "--game-path", game_path, "--preset", preset]
        return await asyncio.to_thread(_run, cmd)

    async def toggle(self, appid: str, game_path: str):
        cmd = [str(SCRIPT_PATH), "toggle", "--appid", appid, "--game-path", game_path]
        return await asyncio.to_thread(_run, cmd)

    async def remove(self, game_path: str):
        cmd = [str(SCRIPT_PATH), "remove", "--game-path", game_path]
        return await asyncio.to_thread(_run, cmd)
