const React = require("react");
const {
  ButtonItem,
  definePlugin,
  Dropdown,
  PanelSection,
  PanelSectionRow,
  Spinner,
  TextField,
} = require("decky-frontend-lib");

const PRESETS = [
  { label: "PSX CRT", value: "presets/psx_crt.ini" },
  { label: "Clean Bloom", value: "presets/clean_bloom.ini" },
  { label: "Performance Sharp", value: "presets/perf_sharp.ini" },
];

const APIS = [
  { data: "d3d9", label: "d3d9" },
  { data: "dxgi", label: "dxgi" },
  { data: "opengl32", label: "opengl32" },
  { data: "d3d8", label: "d3d8" },
];

function useGames(serverAPI) {
  const [games, setGames] = React.useState([]);
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState(null);

  const reload = async () => {
    setLoading(true);
    setError(null);
    const res = await serverAPI.callPluginMethod("list_games", {});
    if (res.success && res.result && res.result.games) {
      setGames(res.result.games);
      if (res.result.stderr) setError(res.result.stderr);
    } else {
      setError(String(res.result || "Failed to list games"));
    }
    setLoading(false);
  };

  React.useEffect(() => {
    reload();
  }, []);

  return { games, loading, error, reload };
}

function runTask(serverAPI, fn, args, label, setTask) {
  return async () => {
    setTask({ state: "running", label });
    const res = await serverAPI.callPluginMethod(fn, args);
    const ok =
      (res.success && res.result && (res.result.code === 0 || res.result.code === undefined)) ||
      false;
    const detail =
      (res.result && (res.result.stderr || res.result.stdout)) ||
      (!res.success ? String(res.result) : undefined);
    setTask({ state: "done", label, ok, detail });
  };
}

function Status({ task }) {
  if (!task || task.state === "idle") return null;
  if (task.state === "running") {
    return React.createElement(
      PanelSectionRow,
      null,
      React.createElement(Spinner, null),
      React.createElement("span", { style: { marginLeft: 8 } }, `Running ${task.label}…`)
    );
  }
  return React.createElement(
    PanelSectionRow,
    null,
    React.createElement(
      "span",
      { style: { color: task.ok ? "var(--gpSystemGreen)" : "var(--gpSystemRed)" } },
      `${task.ok ? "✓" : "⚠"} ${task.label}`
    ),
    task.detail
      ? React.createElement(
          "div",
          { style: { marginTop: 4, opacity: 0.7 } },
          String(task.detail)
        )
      : null
  );
}

function Content({ serverAPI }) {
  const { games, loading, error, reload } = useGames(serverAPI);
  const [selectedAppId, setSelectedAppId] = React.useState(null);
  const [selectedPreset, setSelectedPreset] = React.useState(PRESETS[0].value);
  const [selectedApi, setSelectedApi] = React.useState(APIS[0].data);
  const [customPreset, setCustomPreset] = React.useState("");
  const [task, setTask] = React.useState({ state: "idle" });

  const game = React.useMemo(() => {
    return games.find((g) => g.appid === selectedAppId) || games[0];
  }, [games, selectedAppId]);

  React.useEffect(() => {
    if (games.length && !selectedAppId) setSelectedAppId(games[0].appid);
  }, [games, selectedAppId]);

  const presetToUse = customPreset.trim() || selectedPreset;

  return React.createElement(
    React.Fragment,
    null,
    React.createElement(
      PanelSection,
      { title: "Game" },
      React.createElement(
        PanelSectionRow,
        null,
        loading
          ? React.createElement(Spinner, null)
          : React.createElement(Dropdown, {
              label: "Installed games",
              menuLabel: "Choose game",
              rgOptions: games.map((g) => ({ data: g.appid, label: `${g.name} (${g.appid})` })),
              selectedOption: selectedAppId || (games[0] && games[0].appid),
              onChange: (o) => setSelectedAppId(String(o.data)),
            })
      ),
      game
        ? React.createElement(
            PanelSectionRow,
            null,
            React.createElement("small", { style: { opacity: 0.7 } }, `Path: ${game.path}`)
          )
        : null,
      error
        ? React.createElement(
            PanelSectionRow,
            null,
            React.createElement("small", { style: { color: "var(--gpSystemYellow)" } }, error)
          )
        : null,
      React.createElement(
        PanelSectionRow,
        null,
        React.createElement(
          ButtonItem,
          { layout: "below", onClick: reload },
          "Refresh list"
        )
      )
    ),

    React.createElement(
      PanelSection,
      { title: "Preset & API" },
      React.createElement(
        PanelSectionRow,
        null,
        React.createElement(Dropdown, {
          label: "Preset",
          menuLabel: "Choose preset",
          rgOptions: PRESETS.map((p) => ({ data: p.value, label: p.label })),
          selectedOption: selectedPreset,
          onChange: (o) => setSelectedPreset(String(o.data)),
        })
      ),
      React.createElement(
        PanelSectionRow,
        null,
        React.createElement(TextField, {
          label: "Custom preset path (optional)",
          value: customPreset,
          onChange: (v) => setCustomPreset(v || ""),
          description: "Relative to plugin dir; leave blank to use dropdown preset.",
        })
      ),
      React.createElement(
        PanelSectionRow,
        null,
        React.createElement(Dropdown, {
          label: "Graphics API",
          rgOptions: APIS,
          selectedOption: selectedApi,
          onChange: (o) => setSelectedApi(String(o.data)),
        })
      )
    ),

    React.createElement(
      PanelSection,
      { title: "Actions" },
      React.createElement(
        PanelSectionRow,
        null,
        React.createElement(
          ButtonItem,
          {
            layout: "below",
            disabled: !game,
            onClick:
              game &&
              runTask(
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
              ),
          },
          "Install / Update ReShade"
        )
      ),
      React.createElement(
        PanelSectionRow,
        null,
        React.createElement(
          ButtonItem,
          {
            layout: "below",
            disabled: !game,
            onClick:
              game &&
              runTask(
                serverAPI,
                "apply_preset",
                { game_path: game.path, preset: presetToUse },
                "Apply preset",
                setTask
              ),
          },
          "Apply Preset Only"
        )
      ),
      React.createElement(
        PanelSectionRow,
        null,
        React.createElement(
          ButtonItem,
          {
            layout: "below",
            disabled: !game,
            onClick:
              game &&
              runTask(
                serverAPI,
                "toggle",
                { appid: game.appid, game_path: game.path },
                "Toggle ReShade",
                setTask
              ),
          },
          "Toggle On/Off"
        )
      ),
      React.createElement(
        PanelSectionRow,
        null,
        React.createElement(
          ButtonItem,
          {
            layout: "below",
            disabled: !game,
            onClick:
              game &&
              runTask(
                serverAPI,
                "remove",
                { game_path: game.path },
                "Remove (backup)",
                setTask
              ),
          },
          "Remove (backs up)"
        )
      )
    ),

    React.createElement(
      PanelSection,
      { title: "Status" },
      React.createElement(Status, { task })
    )
  );
}

module.exports = definePlugin((serverAPI) => ({
  title: "Reshady",
  content: React.createElement(Content, { serverAPI }),
  icon: "focus",
}));
