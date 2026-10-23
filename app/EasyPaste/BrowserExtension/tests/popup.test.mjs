import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { page, setDOMParser } from "./helpers.mjs";
setDOMParser();
const manifest = JSON.parse(readFileSync(new URL("../manifest.json", import.meta.url), "utf8"));
const popupHTML = readFileSync(new URL("../popup.html", import.meta.url), "utf8");
let serial = 0;
async function popup(content, url = "https://example.test/article", prepareSite = () => {}) {
  const site = page(content, url), ui = page(popupHTML, "https://extension.test/popup");
  prepareSite(site);
  const writes = [];
  globalThis.document = ui.document;
  globalThis.Option = ui.dom.window.Option;
  globalThis.ClipboardItem = class { constructor(data) { this.data = data; } };
  Object.defineProperty(globalThis, "navigator", { configurable: true, value: { clipboard: { write: async values => writes.push(values), writeText: async value => writes.push(value) } } });
  globalThis.chrome = {
    tabs: { query: async () => [{ id: 42, url }] },
    scripting: { executeScript: async ({ func, files, args = [] }) => files ? [] : [{ frameId: 0, result: await site.dom.window.eval(`(${func.toString()})(...${JSON.stringify(args)})`) }] }
  };
  await import(`../popup.js?test=${serial++}`);
  await idle(ui.document);
  return { ui, site, writes };
}
async function idle(doc) {
  for (let i = 0; i < 200 && doc.body.getAttribute("aria-busy") !== "false"; i++) await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal(doc.body.getAttribute("aria-busy"), "false");
}
test("manifest has only explicit-invocation permissions, no hosts or background worker", () => {
  assert.deepEqual(manifest.permissions, ["activeTab", "scripting", "clipboardWrite"]);
  assert.equal(manifest.host_permissions, undefined); assert.equal(manifest.background, undefined); assert.equal(manifest.content_scripts, undefined);
  assert.match(manifest.content_security_policy.extension_pages, /connect-src 'none'/);
});
test("popup copies HTML and plain text together without exposing the raw page", async () => {
  const { ui, writes } = await popup('<article><h1>Bonjour</h1><p><b>Texte</b><script>evil()</script></p></article>');
  assert.equal(ui.document.getElementById("youtube").hidden, true);
  ui.document.getElementById("copy-page").click(); await idle(ui.document);
  assert.equal(writes.length, 1);
  const data = writes[0][0].data;
  assert.deepEqual(Object.keys(data), ["text/html", "text/plain"]);
  assert.match(await data["text/html"].text(), /<h1/); assert.doesNotMatch(await data["text/html"].text(), /evil/);
  assert.match(await data["text/html"].text(), /<meta name="easypaste-source-url" content="https:\/\/example.test\/article">/);
  assert.match(await data["text/plain"].text(), /Bonjour/);
  assert.equal(ui.document.getElementById("feedback").dataset.kind, "success");
});

test("selected page content keeps address-bar origin even when visible attribution is disabled and page metadata lies", async () => {
  const { ui, writes } = await popup('<meta name="easypaste-source-url" content="https://evil.test/"><link rel="canonical" href="https://evil.test/"><p id="selected">Copie sélectionnée</p>', "https://example.test/article?a=1&b=2", site => {
    const range = site.document.createRange(); range.selectNodeContents(site.document.getElementById("selected"));
    site.dom.window.getSelection().addRange(range);
  });
  ui.document.getElementById("attribution").checked = false;
  assert.equal(ui.document.getElementById("scope").value, "selection");
  ui.document.getElementById("copy-page").click(); await idle(ui.document);
  const data = writes[0][0].data;
  assert.equal(await data["text/plain"].text(), "Copie sélectionnée");
  const rich = await data["text/html"].text();
  assert.match(rich, /https:\/\/example.test\/article\?a=1&amp;b=2/);
  assert.doesNotMatch(rich, /evil|Source :/);
});
test("blocked pages leave copy disabled, with a readable error", async () => {
  const { ui, writes } = await popup("", "chrome://extensions/");
  assert.equal(ui.document.getElementById("copy-page").disabled, true);
  assert.equal(ui.document.getElementById("feedback").dataset.kind, "error");
  assert.equal(writes.length, 0);
});
test("a changed SPA page cannot copy stale content under the old title", async () => {
  const { ui, site, writes } = await popup('<article>Page originale</article>');
  site.dom.reconfigure({ url: "https://example.test/other" });
  ui.document.getElementById("copy-page").click(); await idle(ui.document);
  assert.equal(writes.length, 0); assert.match(ui.document.getElementById("feedback-text").textContent, /changé/);
});
test("clipboard denial never displays a false success", async () => {
  const { ui } = await popup('<article>Bonjour</article>');
  navigator.clipboard.write = async () => { throw new Error("Autorisation de copie refusée."); };
  ui.document.getElementById("copy-page").click(); await idle(ui.document);
  assert.equal(ui.document.getElementById("feedback").dataset.kind, "error");
  assert.equal(ui.document.getElementById("copy-page").disabled, false);
});

test("YouTube without an available track or displayed transcript offers no false download", async () => {
  const { ui } = await popup('<main>Aucune piste</main>', "https://www.youtube.com/watch?v=abcdefghijk");
  assert.equal(ui.document.getElementById("youtube").hidden, false);
  assert.equal(ui.document.getElementById("copy-captions").disabled, true);
  assert.equal(ui.document.getElementById("page-card").open, false);
  assert.match(ui.document.getElementById("caption-info").textContent, /Aucune piste/);
});

test("popup defaults to the native transcript and opens it before copying", async () => {
  const { ui, site, writes } = await popup('<ytd-video-description-transcript-section-renderer><button>Afficher la transcription</button></ytd-video-description-transcript-section-renderer>', "https://www.youtube.com/watch?v=abcdefghijk");
  site.document.querySelector("button").onclick = () => site.document.body.insertAdjacentHTML("beforeend", '<ytd-engagement-panel-section-list-renderer><transcript-segment-view-model><div class="ytwTranscriptSegmentViewModelTimestamp">0:02</div><span class="ytAttributedStringHost" role="text">Essai EasyPaste transcription</span></transcript-segment-view-model></ytd-engagement-panel-section-list-renderer>');
  assert.equal(ui.document.getElementById("track").value, "dom");
  ui.document.getElementById("copy-captions").click(); await idle(ui.document);
  assert.equal(writes.length, 1); assert.match(await writes[0][0].data["text/plain"].text(), /Essai EasyPaste transcription/);
  assert.match(await writes[0][0].data["text/html"].text(), /name="easypaste-source-url"/);
  assert.equal(ui.document.getElementById("feedback").dataset.kind, "success");
});

test("one empty direct track falls back to native; multiple languages never silently substitute one", async () => {
  const content = '<div id="movie_player"></div><ytd-engagement-panel-section-list-renderer><transcript-segment-view-model><div class="ytwTranscriptSegmentViewModelTimestamp">0:02</div><span class="ytAttributedStringHost" role="text">Texte du panneau</span></transcript-segment-view-model></ytd-engagement-panel-section-list-renderer>';
  for (const count of [1, 2]) {
    const { ui, writes } = await popup(content, "https://www.youtube.com/watch?v=abcdefghijk", site => {
      site.document.getElementById("movie_player").getPlayerResponse = () => ({ videoDetails: { videoId: "abcdefghijk" }, captions: { playerCaptionsTracklistRenderer: { captionTracks: Array.from({ length: count }, (_, i) => ({ baseUrl: `https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=${i}`, languageCode: String(i) })) } } });
      site.dom.window.fetch = async () => new Response(""); site.dom.window.TextDecoder = TextDecoder;
    });
    ui.document.getElementById("track").value = "0";
    ui.document.getElementById("copy-captions").click(); await idle(ui.document);
    assert.equal(writes.length, count === 1 ? 1 : 0);
    assert.equal(ui.document.getElementById("feedback").dataset.kind, count === 1 ? "success" : "error");
    if (count === 1) assert.match(await writes[0][0].data["text/plain"].text(), /Texte du panneau/);
    else assert.match(ui.document.getElementById("feedback-text").textContent, /Transcription YouTube/);
  }
});
