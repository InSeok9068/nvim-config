"use strict";

const os = require("os");
const path = require("path");
const Module = require("module");

function runtimeDataDir() {
  if (process.platform === "win32") {
    return path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "nvim-data", "pocketpages-lsp");
  }

  return path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local", "share"), "nvim", "pocketpages-lsp");
}

function runtimeNodeModulesDir() {
  return path.join(runtimeDataDir(), "node_modules");
}

function addRuntimeNodePath() {
  const nodeModulesDir = runtimeNodeModulesDir();
  process.env.NODE_PATH = process.env.NODE_PATH
    ? nodeModulesDir + path.delimiter + process.env.NODE_PATH
    : nodeModulesDir;
  Module._initPaths();
  return nodeModulesDir;
}

module.exports = {
  addRuntimeNodePath,
  runtimeDataDir,
  runtimeNodeModulesDir,
};
