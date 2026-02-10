import React from "react";
import {
  ButtonItem,
  definePlugin,
  Dropdown,
  DropdownOption,
  PanelSection,
  PanelSectionRow,
  ServerAPI,
  Spinner,
  TextField,
  ToggleField,
} from "decky-frontend-lib";
import { useEffect, useMemo, useState } from "react";

type Game = { appid: string; name: string; path: string };

type TaskState =
  | { state: "idle" }
  | { state: "running"; label: string }
  | { state: "done"; label: string; ok: boolean; detail?: string };

const PRESETS: { label: string; value: string }[] = [
  { label: "PSX CRT", value: "presets/psx_crt.ini" },
  { label: "Clean Bloom", value: "presets/clean_bloom.ini" },
  { label: "Performance Sharp", value: "presets/perf_sharp.ini" },
];

const APIS: DropdownOption[] = [
  { data: "d3d9", label: "d3d9" },
  { data: "dxgi", label: "dxgi" },
  { data: "opengl32", label: "opengl32" },
  { data: "d3d8", label: "d3d8" },
];

function useGames(serverAPI: ServerAPI) {
  const [games, setGames] = useState<Game[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const reload = async () => {
    setLoading(true);
    setError(null);
    const res = await serverAPI.callPluginMethod<{ games: Game[]; stderr?: string }>(
      "list_games",
      {}
    );
    if (res.success && res.result?.games) {
      setGames(res.result.games);
      if (res.result.stderr) setError(res.result.stderr);
    } else {
      setError(res.result as unknown as string);
    }
    setLoading(false);
  };

  useEffect(() => {
    reload();
  }, []);

  return { games, loading, error, reload };
}

function runTask(
  serverAPI: ServerAPI,
  fn: string,
  args: Record<string, unknown>,
  label: string,
  setTask: (t: TaskState) => void
) {
  return async () => {
    setTask({ state: "running", label });
    const res = await serverAPI.callPluginMethod<any>(fn, args);
    const ok = !!(res.success && res.result && (res.result as any).code === 0 || res.success);
    const detail =
      (res.result as any)?.stderr ||
      (res.result as any)?.stdout ||
      (!res.success ? String(res.result) : undefined);
    setTask({ state: "done", label, ok, detail });
  };
}

function Status({ task }: { task: TaskState }) {
  if (task.state === "idle") return null;
  if (task.state === "running") return (
    <PanelSectionRow>
      <Spinner /> <span style={{ marginLeft: 8 }}>Running {task.label}…</span>
    </PanelSectionRow>
  );
  return (
    <PanelSectionRow>
      <span style={{ color: task.ok ? "var(--gpSystemGreen)" : "var(--gpSystemRed)" }}>
        {task.ok ? "✓" : "⚠"} {task.label}
      </span>
      {task.detail && <div style={{ marginTop: 4, opacity: 0.7 }}>{task.detail}</div>}
    </PanelSectionRow>
  );
}

function Content({ serverAPI }: { serverAPI: ServerAPI }) {
  const { games, loading, error, reload } = useGames(serverAPI);
  const [selectedAppId, setSelectedAppId] = useState<string | null>(null);
  const [selectedPreset, setSelectedPreset] = useState(PRESETS[0].value);
  const [selectedApi, setSelectedApi] = useState(APIS[0].data as string);
  const [customPreset, setCustomPreset] = useState("");
  const [task, setTask] = useState<TaskState>({ state: "idle" });

  const game = useMemo(
    () => games.find((g) => g.appid === selectedAppId) ?? games[0],
    [games, selectedAppId]
  );

  useEffect(() => {
    if (games.length && !selectedAppId) {
      setSelectedAppId(games[0].appid);
    }
  }, [games]);

  const presetToUse = customPreset.trim() || selectedPreset;

  return (
    <>
      <PanelSection title="Game">
        <PanelSectionRow>
          {loading ? (
            <Spinner />
          ) : (
            <Dropdown
              label="Installed games"
              menuLabel="Choose game"
              rgOptions={games.map((g) => ({ data: g.appid, label: `${g.name} (${g.appid})` }))}
              selectedOption={selectedAppId ?? games[0]?.appid}
              onChange={(o) => setSelectedAppId(String(o.data))}
            />
          )}
        </PanelSectionRow>
        {game && (
          <PanelSectionRow>
            <small style={{ opacity: 0.7 }}>Path: {game.path}</small>
          </PanelSectionRow>
        )}
        {error && (
          <PanelSectionRow>
            <small style={{ color: "var(--gpSystemYellow)" }}>{error}</small>
          </PanelSectionRow>
        )}
        <PanelSectionRow>
          <ButtonItem layout="below" onClick={reload}>
            Refresh list
          </ButtonItem>
        </PanelSectionRow>
      </PanelSection>

      <PanelSection title="Preset & API">
        <PanelSectionRow>
          <Dropdown
            label="Preset"
            menuLabel="Choose preset"
            rgOptions={PRESETS.map((p) => ({ data: p.value, label: p.label }))}
            selectedOption={selectedPreset}
            onChange={(o) => setSelectedPreset(String(o.data))}
          />
        </PanelSectionRow>
        <PanelSectionRow>
          <TextField
            label="Custom preset path (optional)"
            value={customPreset}
            onChange={(v) => setCustomPreset(v ?? "")}
            description="Relative to plugin dir; leave blank to use dropdown preset."
          />
        </PanelSectionRow>
        <PanelSectionRow>
          <Dropdown
            label="Graphics API"
            rgOptions={APIS}
            selectedOption={selectedApi}
            onChange={(o) => setSelectedApi(String(o.data))}
          />
        </PanelSectionRow>
      </PanelSection>

      <PanelSection title="Actions">
        <PanelSectionRow>
          <ButtonItem
            layout="below"
            disabled={!game}
            onClick={
              game
                ? runTask(
                    serverAPI,
                    "install",
                    {
                      appid: game.appid,
                      game_path: game.path,
                      api: selectedApi,
                      preset: presetToUse,
                    },
                    "Install / Update",
                    setTask
                  )
                : undefined
            }
          >
            Install / Update ReShade
          </ButtonItem>
        </PanelSectionRow>
        <PanelSectionRow>
          <ButtonItem
            layout="below"
            disabled={!game}
            onClick={
              game
                ? runTask(
                    serverAPI,
                    "apply_preset",
                    { game_path: game.path, preset: presetToUse },
                    "Apply preset",
                    setTask
                  )
                : undefined
            }
          >
            Apply Preset Only
          </ButtonItem>
        </PanelSectionRow>
        <PanelSectionRow>
          <ButtonItem
            layout="below"
            disabled={!game}
            onClick={
              game
                ? runTask(
                    serverAPI,
                    "toggle",
                    { appid: game.appid, game_path: game.path },
                    "Toggle ReShade",
                    setTask
                  )
                : undefined
            }
          >
            Toggle On/Off
          </ButtonItem>
        </PanelSectionRow>
        <PanelSectionRow>
          <ButtonItem
            layout="below"
            disabled={!game}
            onClick={
              game
                ? runTask(
                    serverAPI,
                    "remove",
                    { game_path: game.path },
                    "Remove (backup)",
                    setTask
                  )
                : undefined
            }
          >
            Remove (backs up)
          </ButtonItem>
        </PanelSectionRow>
      </PanelSection>

      <PanelSection title="Status">
        <Status task={task} />
      </PanelSection>
    </>
  );
}

export default definePlugin((serverAPI: ServerAPI) => {
  return {
    title: "Reshady",
    content: <Content serverAPI={serverAPI} />,
    icon: "focus", // uses built-in icon id
  };
});
