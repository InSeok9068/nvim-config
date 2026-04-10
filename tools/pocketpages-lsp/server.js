#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const {
  CodeActionKind,
  CompletionItemKind,
  DiagnosticSeverity,
  InlayHintKind,
  PositionEncodingKind,
  LSPErrorCodes,
  MarkupKind,
  Position,
  Range,
  ResponseError,
  SignatureInformation,
  ParameterInformation,
  TextDocumentSyncKind,
  createConnection,
  ProposedFeatures,
  TextDocuments,
} = require("vscode-languageserver/node");
const { TextDocument } = require("vscode-languageserver-textdocument");
const { URI } = require("vscode-uri");
const { PocketPagesLanguageServiceManager, findAppRoot, ts } = require("./src/language-service");
const {
  TOKEN_TYPES,
  collectEjsSemanticTokenEntries,
  getTokenTypeIndex,
} = require("./src/ejs-semantic-tokens");

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const manager = new PocketPagesLanguageServiceManager();

const COMPLETION_KIND_MAP = {
  [ts.ScriptElementKind.primitiveType]: CompletionItemKind.Keyword,
  [ts.ScriptElementKind.keyword]: CompletionItemKind.Keyword,
  [ts.ScriptElementKind.constElement]: CompletionItemKind.Constant,
  [ts.ScriptElementKind.letElement]: CompletionItemKind.Variable,
  [ts.ScriptElementKind.variableElement]: CompletionItemKind.Variable,
  [ts.ScriptElementKind.localVariableElement]: CompletionItemKind.Variable,
  [ts.ScriptElementKind.alias]: CompletionItemKind.Reference,
  [ts.ScriptElementKind.memberVariableElement]: CompletionItemKind.Field,
  [ts.ScriptElementKind.memberGetAccessorElement]: CompletionItemKind.Field,
  [ts.ScriptElementKind.memberSetAccessorElement]: CompletionItemKind.Field,
  [ts.ScriptElementKind.functionElement]: CompletionItemKind.Function,
  [ts.ScriptElementKind.localFunctionElement]: CompletionItemKind.Function,
  [ts.ScriptElementKind.memberFunctionElement]: CompletionItemKind.Method,
  [ts.ScriptElementKind.constructSignatureElement]: CompletionItemKind.Constructor,
  [ts.ScriptElementKind.callSignatureElement]: CompletionItemKind.Function,
  [ts.ScriptElementKind.indexSignatureElement]: CompletionItemKind.Property,
  [ts.ScriptElementKind.enumElement]: CompletionItemKind.Enum,
  [ts.ScriptElementKind.moduleElement]: CompletionItemKind.Module,
  [ts.ScriptElementKind.classElement]: CompletionItemKind.Class,
  [ts.ScriptElementKind.interfaceElement]: CompletionItemKind.Interface,
  [ts.ScriptElementKind.warning]: CompletionItemKind.Text,
};

function normalizeDocumentPath(filePath) {
  return String(filePath || "").replace(/\\/g, "/");
}

function uriToFsPath(uri) {
  return URI.parse(uri).fsPath;
}

function fsPathToUri(filePath) {
  const normalizedPath = normalizeDocumentPath(path.resolve(filePath));

  if (/^[A-Za-z]:\//.test(normalizedPath)) {
    return encodeURI("file:///" + normalizedPath);
  }

  return URI.file(filePath).toString();
}

function guessLanguageId(filePath) {
  const normalizedPath = normalizeDocumentPath(filePath);

  if (normalizedPath.endsWith(".ejs")) {
    return "ejs";
  }

  return "javascript";
}

function isExcludedPocketPagesScriptPath(filePath) {
  const normalizedPath = normalizeDocumentPath(filePath);

  if (!normalizedPath.includes("/pb_hooks/pages/")) {
    return false;
  }

  const pagesRelativePath = normalizedPath.split("/pb_hooks/pages/")[1] || "";
  const relativeSegments = pagesRelativePath.split("/").filter(Boolean);

  return (
    relativeSegments.includes("vendor") ||
    normalizedPath.endsWith(".min.js") ||
    normalizedPath.endsWith(".min.cjs") ||
    normalizedPath.endsWith(".min.mjs")
  );
}

function isAnalyzablePocketPagesFilePath(filePath) {
  const normalizedPath = normalizeDocumentPath(filePath);

  if (normalizedPath.endsWith(".ejs")) {
    return !!findAppRoot(filePath);
  }

  if (!normalizedPath.includes("/pb_hooks/pages/")) {
    return false;
  }

  return (
    !isExcludedPocketPagesScriptPath(normalizedPath) &&
    !!findAppRoot(filePath) &&
    (
      normalizedPath.endsWith(".js") ||
      normalizedPath.endsWith(".cjs") ||
      normalizedPath.endsWith(".mjs")
    )
  );
}

function toRange(document, start, end) {
  return Range.create(document.positionAt(start), document.positionAt(end));
}

function getDocumentLines(document) {
  return document.getText().split(/\r?\n/);
}

function toSafeDocumentPosition(document, offset, lines) {
  if (!Number.isFinite(offset)) {
    return null;
  }

  const textLength = document.getText().length;
  const safeOffset = Math.max(0, Math.min(Math.trunc(offset), textLength));
  const position = document.positionAt(safeOffset);
  const lineText = (lines || getDocumentLines(document))[position.line];

  if (typeof lineText !== "string") {
    return null;
  }

  return Position.create(position.line, Math.min(position.character, lineText.length));
}

function toDefinitionLocation(target) {
  if (!target) {
    return null;
  }

  if (typeof target === "string") {
    return {
      uri: fsPathToUri(target),
      range: Range.create(Position.create(0, 0), Position.create(0, 0)),
    };
  }

  return {
    uri: fsPathToUri(target.filePath),
    range: Range.create(
      Position.create(target.line || 0, target.character || 0),
      Position.create(target.line || 0, target.character || 0)
    ),
  };
}

function diagnosticSeverity(category) {
  switch (category) {
    case ts.DiagnosticCategory.Error:
      return DiagnosticSeverity.Error;
    case ts.DiagnosticCategory.Warning:
      return DiagnosticSeverity.Warning;
    case ts.DiagnosticCategory.Suggestion:
      return DiagnosticSeverity.Hint;
    case ts.DiagnosticCategory.Message:
    default:
      return DiagnosticSeverity.Information;
  }
}

function customCompletionKind(category) {
  switch (category) {
    case "resolve-path":
    case "include-path":
    case "route-path":
      return CompletionItemKind.File;
    case "include-local":
      return CompletionItemKind.Property;
    case "collection-name":
      return CompletionItemKind.Struct;
    case "record-field":
      return CompletionItemKind.Field;
    default:
      return CompletionItemKind.Text;
  }
}

function markdownCodeBlock(text, language) {
  return "```" + language + "\n" + String(text || "") + "\n```";
}

function toSignatureHelp(signatureHelpItems) {
  if (!signatureHelpItems || !signatureHelpItems.items || !signatureHelpItems.items.length) {
    return null;
  }

  return {
    activeSignature: signatureHelpItems.selectedItemIndex || 0,
    activeParameter: signatureHelpItems.argumentIndex || 0,
    signatures: signatureHelpItems.items.map((item) => {
      const prefix = ts.displayPartsToString(item.prefixDisplayParts || []);
      const suffix = ts.displayPartsToString(item.suffixDisplayParts || []);
      const separator = ts.displayPartsToString(item.separatorDisplayParts || []);
      let label = prefix;
      const parameters = [];

      item.parameters.forEach((parameter, index) => {
        if (index > 0) {
          label += separator;
        }

        const parameterLabel = ts.displayPartsToString(parameter.displayParts || []);
        const start = label.length;
        label += parameterLabel;
        parameters.push(
          ParameterInformation.create(
            [start, label.length],
            ts.displayPartsToString(parameter.documentation || [])
          )
        );
      });

      label += suffix;

      return SignatureInformation.create(
        label,
        ts.displayPartsToString(item.documentation || []),
        ...parameters
      );
    }),
  };
}

function appRelativePath(filePath) {
  const appRoot = findAppRoot(filePath);
  if (!appRoot) {
    return normalizeDocumentPath(filePath);
  }

  return normalizeDocumentPath(path.relative(appRoot, filePath));
}

function getDocumentForFilePath(filePath) {
  const uri = fsPathToUri(filePath);
  const openDocument = documents.get(uri);
  if (openDocument) {
    return openDocument;
  }

  try {
    return TextDocument.create(uri, guessLanguageId(filePath), 0, fs.readFileSync(filePath, "utf8"));
  } catch (_error) {
    return null;
  }
}

function getServiceForUri(uri) {
  const filePath = uriToFsPath(uri);
  if (!isAnalyzablePocketPagesFilePath(filePath)) {
    return null;
  }

  return manager.getServiceForFile(filePath);
}

function syncDocumentOverride(document) {
  const filePath = uriToFsPath(document.uri);
  if (!isAnalyzablePocketPagesFilePath(filePath)) {
    return;
  }

  const service = manager.getServiceForFile(filePath);
  if (!service) {
    return;
  }

  service.setDocumentOverride(filePath, document.getText());
}

function clearDocumentOverride(document) {
  const filePath = uriToFsPath(document.uri);
  if (!isAnalyzablePocketPagesFilePath(filePath)) {
    return;
  }

  const service = manager.getServiceForFile(filePath);
  if (!service) {
    return;
  }

  service.clearDocumentOverride(filePath);
}

function publishDiagnosticsForDocument(document) {
  const filePath = uriToFsPath(document.uri);
  if (!isAnalyzablePocketPagesFilePath(filePath)) {
    connection.sendDiagnostics({ uri: document.uri, diagnostics: [] });
    return;
  }

  const service = manager.getServiceForFile(filePath);
  if (!service) {
    connection.sendDiagnostics({ uri: document.uri, diagnostics: [] });
    return;
  }

  const diagnostics = service.getDiagnostics(filePath, document.getText()).map((diagnostic) => ({
    range: toRange(document, diagnostic.start, diagnostic.end),
    severity: diagnosticSeverity(diagnostic.category),
    code: diagnostic.code,
    source: "pocketpages",
    message: diagnostic.message,
  }));

  connection.sendDiagnostics({ uri: document.uri, diagnostics });
}

function createWorkspaceTextEdits(edits) {
  const changes = {};

  for (const edit of edits || []) {
    const uri = fsPathToUri(edit.filePath);
    const targetDocument = getDocumentForFilePath(edit.filePath);
    if (!targetDocument) {
      continue;
    }

    changes[uri] = changes[uri] || [];
    changes[uri].push({
      range: toRange(targetDocument, edit.start, edit.end),
      newText: edit.newText,
    });
  }

  return { changes };
}

function withErrorLogging(methodName, handler, fallback) {
  return async (...args) => {
    try {
      return await handler(...args);
    } catch (error) {
      connection.console.error(
        "[pocketpages-lsp] " + methodName + " failed:\n" + (error && error.stack ? error.stack : String(error))
      );
      return fallback;
    }
  };
}

function buildSemanticTokenData(document) {
  const data = [];
  const text = document.getText();
  const entries = collectEjsSemanticTokenEntries(document.getText());
  let prevLine = 0;
  let prevChar = 0;

  for (const entry of entries) {
    const tokenTypeIndex = getTokenTypeIndex(entry.tokenType);
    if (tokenTypeIndex === null) {
      continue;
    }

    const start = document.positionAt(entry.start);
    const end = document.positionAt(entry.start + entry.length);

    if (start.line === end.line) {
      const deltaLine = start.line - prevLine;
      const deltaStart = deltaLine === 0 ? start.character - prevChar : start.character;
      data.push(deltaLine, deltaStart, entry.length, tokenTypeIndex, 0);
      prevLine = start.line;
      prevChar = start.character;
      continue;
    }

    let currentOffset = entry.start;
    while (currentOffset < entry.start + entry.length) {
      const currentStart = document.positionAt(currentOffset);
      const newlineOffset = text.indexOf("\n", currentOffset);
      const lineEndOffset = newlineOffset === -1 ? text.length : newlineOffset;
      const chunkEnd = Math.min(lineEndOffset, entry.start + entry.length);
      const chunkLength = chunkEnd - currentOffset;

      if (chunkLength > 0) {
        const deltaLine = currentStart.line - prevLine;
        const deltaStart = deltaLine === 0 ? currentStart.character - prevChar : currentStart.character;
        data.push(deltaLine, deltaStart, chunkLength, tokenTypeIndex, 0);
        prevLine = currentStart.line;
        prevChar = currentStart.character;
      }

      if (chunkEnd === currentOffset) {
        currentOffset += 1;
      } else {
        currentOffset = chunkEnd;
      }
    }
  }

  return data;
}

connection.onInitialize(() => ({
  positionEncoding: PositionEncodingKind.UTF16,
  capabilities: {
    textDocumentSync: TextDocumentSyncKind.Incremental,
    completionProvider: {
      resolveProvider: true,
      triggerCharacters: [".", "'", "\"", "/", "{", ","],
    },
    hoverProvider: true,
    definitionProvider: true,
    referencesProvider: true,
    renameProvider: {
      prepareProvider: true,
    },
    signatureHelpProvider: {
      triggerCharacters: ["(", ","],
      retriggerCharacters: [","],
    },
    codeActionProvider: true,
    documentLinkProvider: {
      resolveProvider: false,
    },
    inlayHintProvider: true,
    semanticTokensProvider: {
      full: true,
      legend: {
        tokenTypes: TOKEN_TYPES,
        tokenModifiers: [],
      },
    },
  },
}));

connection.onCompletion(
  withErrorLogging("completion", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    const service = getServiceForUri(document.uri);
    if (!service) {
      return null;
    }

    const offset = document.offsetAt(params.position);
    const customCompletionData = service.getCustomCompletionData(filePath, document.getText(), offset);

    if (customCompletionData) {
      return customCompletionData.items.map((entry) => ({
        label: entry.label,
        kind: customCompletionKind(entry.category),
        insertText: entry.insertText || entry.label,
        detail: entry.detail || "",
        sortText: entry.sortText,
        documentation: entry.documentation
          ? { kind: MarkupKind.Markdown, value: String(entry.documentation) }
          : undefined,
        textEdit: {
          range: toRange(document, customCompletionData.start, customCompletionData.end),
          newText: entry.insertText || entry.label,
        },
      }));
    }

    const completionData = service.getCompletionData(filePath, document.getText(), offset);
    if (!completionData) {
      return null;
    }

    return completionData.entries.map((entry) => ({
      label: entry.name,
      kind: COMPLETION_KIND_MAP[entry.kind] || CompletionItemKind.Text,
      sortText: entry.sortText,
      insertText: entry.insertText || entry.name,
      detail: entry.kindModifiers ? entry.kind + " " + entry.kindModifiers : entry.kind,
      filterText: entry.insertText || entry.name,
      data: {
        filePath,
        virtualFileName: completionData.virtualFileName,
        virtualOffset: completionData.virtualOffset,
        name: entry.name,
        source: entry.source,
      },
      textEdit: completionData.replacementSpan
        ? {
            range: toRange(
              document,
              completionData.replacementSpan.start,
              completionData.replacementSpan.end
            ),
            newText: entry.insertText || entry.name,
          }
        : undefined,
    }));
  }, null)
);

connection.onCompletionResolve(
  withErrorLogging("completionResolve", (item) => {
    if (!item.data) {
      return item;
    }

    const service = manager.getServiceForFile(item.data.filePath);
    if (!service) {
      return item;
    }

    const details = service.getCompletionDetails(
      item.data.virtualFileName,
      item.data.virtualOffset,
      item.data.name,
      item.data.source
    );

    if (!details) {
      return item;
    }

    const signature = ts.displayPartsToString(details.displayParts || []);
    const documentation = ts.displayPartsToString(details.documentation || []);

    if (signature) {
      item.detail = signature;
    }

    if (signature || documentation) {
      item.documentation = {
        kind: MarkupKind.Markdown,
        value: [signature ? markdownCodeBlock(signature, "ts") : "", documentation].filter(Boolean).join("\n\n"),
      };
    }

    return item;
  }, null)
);

connection.onHover(
  withErrorLogging("hover", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    const service = getServiceForUri(document.uri);
    if (!service) {
      return null;
    }

    const offset = document.offsetAt(params.position);
    const quickInfo = service.getQuickInfo(filePath, document.getText(), offset);
    const pathTargetInfo = service.getPathTargetInfo(filePath, document.getText(), offset);

    if ((!quickInfo || quickInfo.start === null || quickInfo.end === null) && !pathTargetInfo) {
      return null;
    }

    const contents = [];

    if (quickInfo && quickInfo.displayText) {
      contents.push(markdownCodeBlock(quickInfo.displayText, "ts"));
    }

    if (quickInfo && quickInfo.documentation) {
      contents.push(quickInfo.documentation);
    }

    if (pathTargetInfo && pathTargetInfo.targetFilePath) {
      const pathLines = ["Target: `" + appRelativePath(pathTargetInfo.targetFilePath) + "`"];
      if (pathTargetInfo.kind === "route-path" && pathTargetInfo.value) {
        pathLines.push("Route: `" + pathTargetInfo.value + "`");
      }
      contents.push(pathLines.join("\n\n"));
    }

    const hoverRange =
      quickInfo && quickInfo.start !== null && quickInfo.end !== null
        ? toRange(document, quickInfo.start, quickInfo.end)
        : toRange(document, pathTargetInfo.start, pathTargetInfo.end);

    return {
      contents: {
        kind: MarkupKind.Markdown,
        value: contents.join("\n\n"),
      },
      range: hoverRange,
    };
  }, null)
);

connection.onSignatureHelp(
  withErrorLogging("signatureHelp", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    const service = getServiceForUri(document.uri);
    if (!service) {
      return null;
    }

    const offset = document.offsetAt(params.position);
    return toSignatureHelp(
      service.getSignatureHelp(filePath, document.getText(), offset, {
        triggerCharacter: params.context ? params.context.triggerCharacter : undefined,
        isRetrigger: !!(params.context && params.context.isRetrigger),
      })
    );
  }, null)
);

connection.onDefinition(
  withErrorLogging("definition", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    const service = getServiceForUri(document.uri);
    if (!service) {
      return null;
    }

    const offset = document.offsetAt(params.position);
    return toDefinitionLocation(service.getDefinitionTarget(filePath, document.getText(), offset));
  }, null)
);

connection.onReferences(
  withErrorLogging("references", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    const service = getServiceForUri(document.uri);
    if (!service) {
      return null;
    }

    const offset = document.offsetAt(params.position);
    const references = service.getReferenceTargets(filePath, document.getText(), offset, {
      includeDeclaration: !!(params.context && params.context.includeDeclaration),
    });

    if (!references || !references.length) {
      return null;
    }

    return references.map((reference) => {
      const uri = fsPathToUri(reference.filePath);
      const targetDocument = getDocumentForFilePath(reference.filePath);
      if (!targetDocument) {
        return null;
      }

      return {
        uri,
        range: toRange(targetDocument, reference.start, reference.end),
      };
    }).filter(Boolean);
  }, null)
);

connection.onPrepareRename(
  withErrorLogging("prepareRename", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    const service = getServiceForUri(document.uri);
    if (!service) {
      return null;
    }

    const offset = document.offsetAt(params.position);
    const renameInfo = service.getRenameInfo(filePath, document.getText(), offset);
    if (!renameInfo) {
      return null;
    }

    if (!renameInfo.canRename) {
      throw new ResponseError(
        LSPErrorCodes.RequestFailed,
        renameInfo.localizedErrorMessage || "Unable to rename this symbol."
      );
    }

    return {
      range: toRange(document, renameInfo.start, renameInfo.end),
      placeholder: renameInfo.placeholder,
    };
  }, null)
);

connection.onRenameRequest(
  withErrorLogging("rename", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    const service = getServiceForUri(document.uri);
    if (!service) {
      return null;
    }

    const offset = document.offsetAt(params.position);
    const renameResult = service.getRenameEdits(filePath, document.getText(), offset, params.newName);
    if (!renameResult) {
      return null;
    }

    if (!renameResult.canRename) {
      throw new ResponseError(
        LSPErrorCodes.RequestFailed,
        renameResult.localizedErrorMessage || "Unable to rename this symbol."
      );
    }

    return createWorkspaceTextEdits(renameResult.edits);
  }, null)
);

connection.onCodeAction(
  withErrorLogging("codeAction", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    const service = getServiceForUri(document.uri);
    if (!service) {
      return null;
    }

    const actionSpecs = service.getCodeActions(filePath, document.getText(), {
      start: document.offsetAt(params.range.start),
      end: document.offsetAt(params.range.end),
    });

    if (!actionSpecs || !actionSpecs.length) {
      return null;
    }

    return actionSpecs.map((actionSpec) => ({
      title: actionSpec.title,
      kind: CodeActionKind.QuickFix,
      edit: createWorkspaceTextEdits(actionSpec.edits),
    }));
  }, null)
);

connection.onDocumentLinks(
  withErrorLogging("documentLinks", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    const service = getServiceForUri(document.uri);
    if (!service) {
      return null;
    }

    return service.getDocumentLinks(filePath, document.getText()).map((entry) => ({
      range: toRange(document, entry.start, entry.end),
      target: fsPathToUri(entry.targetFilePath),
      tooltip:
        entry.kind === "resolve-path"
          ? "Open module target: " + entry.value
          : entry.kind === "include-path"
            ? "Open partial target: " + entry.value
            : "Open route target: " + entry.value,
    }));
  }, null)
);

connection.languages.inlayHint.on(
  withErrorLogging("inlayHint", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    const service = getServiceForUri(document.uri);
    if (!service) {
      return null;
    }

    const lines = getDocumentLines(document);

    return service.getInlayHintEntries(filePath, document.getText(), {
      start: document.offsetAt(params.range.start),
      end: document.offsetAt(params.range.end),
    }).flatMap((entry) => {
      const position = toSafeDocumentPosition(document, entry.position, lines);
      if (!position) {
        return [];
      }

      return [{
        position,
        label: entry.label,
        kind: entry.kind === "parameter" ? InlayHintKind.Parameter : InlayHintKind.Type,
        paddingLeft: true,
        tooltip: entry.tooltip,
      }];
    });
  }, null)
);

connection.languages.semanticTokens.on(
  withErrorLogging("semanticTokens", (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
      return null;
    }

    const filePath = uriToFsPath(document.uri);
    if (!normalizeDocumentPath(filePath).endsWith(".ejs")) {
      return { data: [] };
    }

    const service = getServiceForUri(document.uri);
    if (!service) {
      return { data: [] };
    }

    return {
      data: buildSemanticTokenData(document),
    };
  }, null)
);

documents.onDidOpen((event) => {
  syncDocumentOverride(event.document);
  publishDiagnosticsForDocument(event.document);
});

documents.onDidChangeContent((event) => {
  syncDocumentOverride(event.document);
  publishDiagnosticsForDocument(event.document);
});

documents.onDidClose((event) => {
  clearDocumentOverride(event.document);
  connection.sendDiagnostics({ uri: event.document.uri, diagnostics: [] });
});

process.on("uncaughtException", (error) => {
  connection.console.error(
    "[pocketpages-lsp] uncaughtException:\n" + (error && error.stack ? error.stack : String(error))
  );
});

process.on("unhandledRejection", (error) => {
  connection.console.error(
    "[pocketpages-lsp] unhandledRejection:\n" + (error && error.stack ? error.stack : String(error))
  );
});

documents.listen(connection);
connection.listen();
