import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function readJson(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function readProjectPrettierConfig(root) {
  const prettierConfig = readJson(path.join(root, ".prettierrc"));
  if (
    prettierConfig &&
    typeof prettierConfig === "object" &&
    !Array.isArray(prettierConfig)
  ) {
    return prettierConfig;
  }

  const prettierJsonConfig = readJson(path.join(root, ".prettierrc.json"));
  if (
    prettierJsonConfig &&
    typeof prettierJsonConfig === "object" &&
    !Array.isArray(prettierJsonConfig)
  ) {
    return prettierJsonConfig;
  }

  const packageJson = readJson(path.join(root, "package.json"));
  if (
    packageJson &&
    packageJson.prettier &&
    typeof packageJson.prettier === "object" &&
    !Array.isArray(packageJson.prettier)
  ) {
    return packageJson.prettier;
  }

  return {};
}

const projectConfig = { ...readProjectPrettierConfig(process.cwd()) };
delete projectConfig.plugins;

export default {
  ...projectConfig,
  plugins: [path.join(__dirname, "prettier-plugin-ejs-safe.mjs")],
};
