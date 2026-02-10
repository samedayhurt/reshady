#!/usr/bin/env node
import { build } from "esbuild";
import { dirname, resolve } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");

const watch = process.argv.includes("--watch");

const shared = {
  entryPoints: [resolve(root, "src/index.tsx")],
  bundle: true,
  platform: "node",
  format: "cjs",
  target: "node18",
  external: ["decky-frontend-lib"],
  outfile: resolve(root, "dist/index.js"),
  loader: { ".png": "file", ".svg": "file" },
};

async function run() {
  if (watch) {
    const ctx = await build({ ...shared, watch: true, sourcemap: "inline" });
    console.log("Watching for changes...");
    return ctx;
  }
  await build(shared);
  console.log("Built dist/index.js");
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
