"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const { URI } = require("vscode-uri");

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeFile(filePath, content) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, content, "utf8");
}

function normalizePath(filePath) {
  return String(filePath || "").replace(/\\/g, "/");
}

function normalizeUriPath(value) {
  const stringValue = String(value || "");

  if (stringValue.startsWith("file:")) {
    return normalizePath(URI.parse(stringValue).fsPath);
  }

  return normalizePath(stringValue);
}

function offsetToPosition(text, offset) {
  const before = text.slice(0, offset);
  const lines = before.split(/\r?\n/);
  return {
    line: lines.length - 1,
    character: lines[lines.length - 1].length,
  };
}

function findPosition(text, needle, delta) {
  const index = text.indexOf(needle);
  if (index === -1) {
    throw new Error("Needle not found: " + needle);
  }

  return offsetToPosition(text, index + (delta || 0));
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function createFixtureApp() {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "pocketpages-lsp-fixture-"));
  const appRoot = path.join(fixtureRoot, "apps", "fixture-app");

  writeFile(
    path.join(appRoot, "jsconfig.json"),
    JSON.stringify(
      {
        include: ["pb_data/types.d.ts", "pocketpages-globals.d.ts", "types.d.ts", "**/*.ejs", "**/*.js"],
        compilerOptions: { module: "commonjs" },
      },
      null,
      2
    )
  );

  writeFile(
    path.join(appRoot, "pb_data", "types.d.ts"),
    `declare namespace core {
  interface Record {
    id: string
    get(name: string): any
  }
}

declare namespace pocketbase {
  interface PocketBase {
    findFirstRecordByFilter(collectionModelOrIdentifier: any, filter: string, params?: Record<string, any>): core.Record
  }
}

declare var $app: pocketbase.PocketBase
`
  );

  writeFile(
    path.join(appRoot, "pocketpages-globals.d.ts"),
    `type PagesRequestContext<TData = any> = {
  body: () => Record<string, any> | string
  formData: () => Record<string, any> | string
  meta: (key: string, value?: string) => string | undefined
  params: Record<string, string | undefined>
  redirect: (path: string, options?: Record<string, any>) => void
  request: {
    method: string
    auth?: core.Record
  }
  resolve: (path: string) => any
}

type PagesResponse = {
  json: (status: number, payload: any) => void
}

declare global {
  interface PocketPagesRouteParams {
    boardSlug?: string
  }

  const body: PagesRequestContext<any>["body"]
  const formData: PagesRequestContext<any>["formData"]
  const meta: PagesRequestContext<any>["meta"]
  const params: PagesRequestContext<any>["params"] & PocketPagesRouteParams
  const redirect: PagesRequestContext<any>["redirect"]
  const request: PagesRequestContext<any>["request"]
  const resolve: PagesRequestContext<any>["resolve"]
  const response: PagesResponse
  const include: (path: string, data?: Record<string, any>) => string
  const signInWithPassword: (email: string, password: string, options?: { collection?: string }) => {
    token: string
    record: core.Record
  }
}

export {}
`
  );

  writeFile(
    path.join(appRoot, "types.d.ts"),
    `declare namespace types {
  type FixtureAuthState = {
    ok: boolean
    method: string
  }
}
`
  );

  writeFile(
    path.join(appRoot, "pb_schema.json"),
    JSON.stringify(
      [
        {
          name: "boards",
          fields: [
            { name: "name", type: "text" },
            { name: "slug", type: "text" },
          ],
        },
      ],
      null,
      2
    )
  );

  const indexText = `<script server>
const boardService = resolve('board-service')
const flashMessage = String(params.message || '')
const authState = boardService.readAuthState({ request })
const boardRecord = $app.findFirstRecordByFilter('boards', 'slug = {:slug}', { slug: params.boardSlug })
const boardName = boardRecord.get('name')
signInWithPassword('demo@example.com', 'pw')
</script>
<a href="/sign-in">Sign in</a>
<%- include('flash-alert.ejs', { flashMessage }) %>
`;
  const badRouteText = `<a href="/signn-in?next=/boards"></a>\n`;
  const consumerText = `const boardService = require('./board-service')\nboardService.readAuthState({ request })\n`;

  writeFile(path.join(appRoot, "pb_hooks", "pages", "(site)", "index.ejs"), indexText);
  writeFile(path.join(appRoot, "pb_hooks", "pages", "(site)", "bad-route.ejs"), badRouteText);
  writeFile(path.join(appRoot, "pb_hooks", "pages", "(site)", "sign-in.ejs"), `<h1>Sign in</h1>\n`);
  writeFile(
    path.join(appRoot, "pb_hooks", "pages", "_private", "board-service.js"),
    `/**
 * @param {{ request: { method: string } }} params
 * @returns {types.FixtureAuthState}
 */
function readAuthState(params) {
  return {
    ok: !!params,
    method: params.request.method,
  }
}

module.exports = {
  readAuthState,
}
`
  );
  writeFile(path.join(appRoot, "pb_hooks", "pages", "_private", "consumer.js"), consumerText);
  writeFile(
    path.join(appRoot, "pb_hooks", "pages", "_private", "flash-alert.ejs"),
    `<div><%= flashMessage %></div>\n`
  );

  return {
    fixtureRoot,
    appRoot,
    indexFilePath: path.join(appRoot, "pb_hooks", "pages", "(site)", "index.ejs"),
    badRouteFilePath: path.join(appRoot, "pb_hooks", "pages", "(site)", "bad-route.ejs"),
    serviceFilePath: path.join(appRoot, "pb_hooks", "pages", "_private", "board-service.js"),
    consumerFilePath: path.join(appRoot, "pb_hooks", "pages", "_private", "consumer.js"),
    indexText,
    badRouteText,
    consumerText,
  };
}

class JsonRpcClient {
  constructor(serverPath) {
    this.proc = spawn("node", [serverPath, "--stdio"], { stdio: ["pipe", "pipe", "pipe"] });
    this.buffer = "";
    this.nextId = 1;
    this.pending = new Map();
    this.notifications = [];
    this.waiters = [];

    this.proc.stdout.on("data", (chunk) => {
      this.buffer += chunk.toString("utf8");
      this._drain();
    });

    this.proc.stderr.on("data", (chunk) => {
      process.stderr.write(chunk);
    });
  }

  _drain() {
    while (true) {
      const headerEnd = this.buffer.indexOf("\r\n\r\n");
      if (headerEnd === -1) {
        return;
      }

      const header = this.buffer.slice(0, headerEnd);
      const match = header.match(/Content-Length: (\d+)/i);
      if (!match) {
        return;
      }

      const length = Number(match[1]);
      const start = headerEnd + 4;
      if (this.buffer.length < start + length) {
        return;
      }

      const body = this.buffer.slice(start, start + length);
      this.buffer = this.buffer.slice(start + length);
      const message = JSON.parse(body);

      if (Object.prototype.hasOwnProperty.call(message, "id")) {
        const pending = this.pending.get(message.id);
        if (pending) {
          this.pending.delete(message.id);
          pending.resolve(message.result);
        }
        continue;
      }

      this.notifications.push(message);
      this.waiters = this.waiters.filter((waiter) => {
        if (waiter.method !== message.method) {
          return true;
        }

        if (waiter.predicate && !waiter.predicate(message.params)) {
          return true;
        }

        waiter.resolve(message.params);
        return false;
      });
    }
  }

  request(method, params) {
    const id = this.nextId++;
    const body = JSON.stringify({ jsonrpc: "2.0", id, method, params });
    this.proc.stdin.write("Content-Length: " + Buffer.byteLength(body, "utf8") + "\r\n\r\n" + body);

    return new Promise((resolve) => {
      this.pending.set(id, { resolve });
    });
  }

  notify(method, params) {
    const body = JSON.stringify({ jsonrpc: "2.0", method, params });
    this.proc.stdin.write("Content-Length: " + Buffer.byteLength(body, "utf8") + "\r\n\r\n" + body);
  }

  waitForNotification(method, predicate, timeoutMs) {
    for (const notification of this.notifications) {
      if (notification.method !== method) {
        continue;
      }
      if (predicate && !predicate(notification.params)) {
        continue;
      }
      return Promise.resolve(notification.params);
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.waiters = this.waiters.filter((waiter) => waiter.resolve !== resolve);
        reject(new Error("Timed out waiting for notification: " + method));
      }, timeoutMs || 5000);

      this.waiters.push({
        method,
        predicate,
        resolve: (params) => {
          clearTimeout(timeout);
          resolve(params);
        },
      });
    });
  }

  async initialize(rootPath) {
    const rootUri = URI.file(rootPath).toString();
    const capabilities = await this.request("initialize", {
      processId: null,
      rootUri,
      capabilities: {},
      workspaceFolders: [{ uri: rootUri, name: rootPath }],
    });
    this.notify("initialized", {});
    return capabilities;
  }

  openFile(filePath, text, languageId) {
    this.notify("textDocument/didOpen", {
      textDocument: {
        uri: URI.file(filePath).toString(),
        languageId,
        version: 1,
        text,
      },
    });
  }

  close() {
    this.proc.kill();
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function run() {
  const fixture = createFixtureApp();
  const client = new JsonRpcClient(path.resolve(__dirname, "..", "server.js"));

  try {
    const capabilities = await client.initialize(fixture.appRoot);
    assert(!!capabilities.capabilities.completionProvider, "missing completionProvider");
    assert(!!capabilities.capabilities.hoverProvider, "missing hoverProvider");
    assert(!!capabilities.capabilities.definitionProvider, "missing definitionProvider");
    assert(!!capabilities.capabilities.referencesProvider, "missing referencesProvider");
    assert(!!capabilities.capabilities.renameProvider, "missing renameProvider");
    assert(!!capabilities.capabilities.codeActionProvider, "missing codeActionProvider");
    assert(!!capabilities.capabilities.documentLinkProvider, "missing documentLinkProvider");
    assert(!!capabilities.capabilities.inlayHintProvider, "missing inlayHintProvider");
    assert(!!capabilities.capabilities.semanticTokensProvider, "missing semanticTokensProvider");

    client.openFile(fixture.indexFilePath, fixture.indexText, "ejs");
    await wait(200);

    const completion = await client.request("textDocument/completion", {
      textDocument: { uri: URI.file(fixture.indexFilePath).toString() },
      position: findPosition(fixture.indexText, "boardService.", "boardService.".length),
    });
    const completionItems = completion.items || completion;
    assert(completionItems.some((item) => item.label === "readAuthState"), "expected boardService.readAuthState completion");

    const hover = await client.request("textDocument/hover", {
      textDocument: { uri: URI.file(fixture.indexFilePath).toString() },
      position: findPosition(fixture.indexText, "params", 1),
    });
    assert(
      normalizePath(JSON.stringify(hover.contents)).includes("PocketPagesRouteParams"),
      "expected params hover type"
    );

    const definition = await client.request("textDocument/definition", {
      textDocument: { uri: URI.file(fixture.indexFilePath).toString() },
      position: findPosition(fixture.indexText, "board-service", 3),
    });
    assert(
      normalizeUriPath(definition.uri).endsWith("/pb_hooks/pages/_private/board-service.js"),
      "expected resolve() definition target"
    );

    const documentLinks = await client.request("textDocument/documentLink", {
      textDocument: { uri: URI.file(fixture.indexFilePath).toString() },
    });
    const linkTargets = documentLinks.map((entry) => normalizeUriPath(entry.target));
    assert(
      linkTargets.some((target) => target.endsWith("/pb_hooks/pages/_private/board-service.js")),
      "expected board-service document link"
    );
    assert(
      linkTargets.some((target) => target.endsWith("/pb_hooks/pages/_private/flash-alert.ejs")),
      "expected flash-alert document link"
    );
    assert(
      linkTargets.some((target) => target.endsWith("/pb_hooks/pages/(site)/sign-in.ejs")),
      "expected sign-in route document link"
    );

    const references = await client.request("textDocument/references", {
      textDocument: { uri: URI.file(fixture.indexFilePath).toString() },
      position: findPosition(fixture.indexText, "readAuthState", 2),
      context: { includeDeclaration: true },
    });
    const referenceTargets = references.map((entry) => normalizeUriPath(entry.uri));
    assert(
      referenceTargets.some((target) => target.endsWith("/pb_hooks/pages/_private/board-service.js")),
      "expected readAuthState definition reference"
    );
    assert(
      referenceTargets.some((target) => target.endsWith("/pb_hooks/pages/(site)/index.ejs")),
      "expected readAuthState usage reference"
    );

    const rename = await client.request("textDocument/rename", {
      textDocument: { uri: URI.file(fixture.indexFilePath).toString() },
      position: findPosition(fixture.indexText, "readAuthState", 2),
      newName: "readSessionState",
    });
    const renamedUris = Object.keys(rename.changes || {}).map((entry) => normalizeUriPath(entry));
    assert(
      renamedUris.some((target) => target.endsWith("/pb_hooks/pages/_private/board-service.js")),
      "expected rename edit for service file"
    );
    assert(
      renamedUris.some((target) => target.endsWith("/pb_hooks/pages/(site)/index.ejs")),
      "expected rename edit for caller file"
    );

    const signatureHelp = await client.request("textDocument/signatureHelp", {
      textDocument: { uri: URI.file(fixture.indexFilePath).toString() },
      position: findPosition(fixture.indexText, "signInWithPassword(", "signInWithPassword(".length),
      context: { triggerKind: 1, isRetrigger: false, triggerCharacter: "(" },
    });
    assert(signatureHelp && signatureHelp.signatures && signatureHelp.signatures.length > 0, "expected signatureHelp");

    const inlayHints = await client.request("textDocument/inlayHint", {
      textDocument: { uri: URI.file(fixture.indexFilePath).toString() },
      range: {
        start: { line: 0, character: 0 },
        end: offsetToPosition(fixture.indexText, fixture.indexText.length),
      },
    });
    assert(Array.isArray(inlayHints) && inlayHints.length > 0, "expected inlay hints");

    const semanticTokens = await client.request("textDocument/semanticTokens/full", {
      textDocument: { uri: URI.file(fixture.indexFilePath).toString() },
    });
    assert(Array.isArray(semanticTokens.data) && semanticTokens.data.length > 0, "expected semantic tokens");

    client.openFile(fixture.badRouteFilePath, fixture.badRouteText, "ejs");
    const diagnostics = await client.waitForNotification(
      "textDocument/publishDiagnostics",
      (params) => normalizeUriPath(params.uri).endsWith("/pb_hooks/pages/(site)/bad-route.ejs"),
      5000
    );
    assert(
      diagnostics.diagnostics.some((entry) => entry.code === "pp-unresolved-route-path"),
      "expected unresolved route diagnostic"
    );

    const routeStart = fixture.badRouteText.indexOf("/signn-in?next=/boards");
    const routeEnd = routeStart + "/signn-in?next=/boards".length;
    const codeActions = await client.request("textDocument/codeAction", {
      textDocument: { uri: URI.file(fixture.badRouteFilePath).toString() },
      range: {
        start: offsetToPosition(fixture.badRouteText, routeStart),
        end: offsetToPosition(fixture.badRouteText, routeEnd),
      },
      context: { diagnostics: diagnostics.diagnostics },
    });
    assert(
      codeActions.some((entry) =>
        Object.values(entry.edit.changes || {})
          .flat()
          .some((edit) => edit.newText === "/sign-in?next=/boards")
      ),
      "expected route quick fix"
    );

    client.openFile(fixture.serviceFilePath, fs.readFileSync(fixture.serviceFilePath, "utf8"), "javascript");
    await wait(200);
    const serviceHover = await client.request("textDocument/hover", {
      textDocument: { uri: URI.file(fixture.serviceFilePath).toString() },
      position: findPosition(fs.readFileSync(fixture.serviceFilePath, "utf8"), "readAuthState", 2),
    });
    assert(
      normalizePath(JSON.stringify(serviceHover.contents)).includes("readAuthState"),
      "expected JS hover on private module member"
    );

    console.log("Smoke test passed.");
    console.log("Capabilities: completion, hover, definition, references, rename, signatureHelp, codeAction, documentLink, inlayHint, semanticTokens");
    console.log("Cross-file checks: resolve() definition, module references, rename edits, route diagnostics/codeAction");
  } finally {
    client.close();
    fs.rmSync(fixture.fixtureRoot, { recursive: true, force: true });
  }
}

run().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exitCode = 1;
});
