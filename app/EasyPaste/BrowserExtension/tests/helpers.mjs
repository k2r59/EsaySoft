import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
const require = createRequire(import.meta.url);
const { JSDOM } = require("jsdom");
const source = readFileSync(new URL("../src/content.js", import.meta.url), "utf8");
const transcriptSource = readFileSync(new URL("../src/transcript.js", import.meta.url), "utf8");
export function page(html, url = "https://example.test/article") {
  const dom = new JSDOM(`<!doctype html><html><head><title>Article d’essai</title></head><body>${html}</body></html>`, { url, runScripts: "outside-only" });
  dom.window.eval(source);
  dom.window.eval(transcriptSource);
  return { dom, document: dom.window.document, api: dom.window.EasyPasteWeb };
}
export function setDOMParser() {
  const dom = new JSDOM("");
  globalThis.DOMParser = dom.window.DOMParser;
  return dom;
}
