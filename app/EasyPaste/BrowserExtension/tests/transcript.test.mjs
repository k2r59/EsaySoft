import { test } from "node:test";
import assert from "node:assert/strict";
import { page } from "./helpers.mjs";
import { readCaptionTrack } from "../src/youtube.js";

const video = "abcdefghijk", url = `https://www.youtube.com/watch?v=${video}`;
const row = (stamp, text) => `<transcript-segment-view-model><div class="ytwTranscriptSegmentViewModelTimestamp"><span class="ytAttributedStringHost">${stamp}</span></div><span class="ytAttributedStringHost" role="text">${text}</span></transcript-segment-view-model>`;
const panel = rows => `<ytd-engagement-panel-section-list-renderer target-id="PAmodern_transcript_view" visibility="ENGAGEMENT_PANEL_VISIBILITY_EXPANDED">${rows}</ytd-engagement-panel-section-list-renderer>`;

test("modern transcript panel and attributed text are recognized without mixing timestamps", () => {
  const context = page(panel(row("1:05", "Bonjour &amp; merci") + row("1:06", "Deuxième phrase")), url);
  const result = context.dom.window.EasyPasteTranscript.read(video);
  assert.equal(result.cues.length, 2); assert.equal(result.cues[0].text, "Bonjour & merci"); assert.equal(result.cues[0].start, 65);
  context.document.querySelector("ytd-engagement-panel-section-list-renderer").removeAttribute("target-id");
  assert.equal(context.dom.window.EasyPasteTranscript.read(video).cues.length, 2);
});
test("native transcript opens on explicit collection and waits for YouTube's asynchronous rendering", async () => {
  const context = page('<ytd-video-description-transcript-section-renderer><button>Afficher la transcription</button></ytd-video-description-transcript-section-renderer>', url);
  let clicked = 0;
  context.document.querySelector("button").onclick = () => { clicked++; setTimeout(() => context.document.body.insertAdjacentHTML("beforeend", panel(row("0:00", "Test natif"))), 50); };
  assert.equal(context.dom.window.EasyPasteTranscript.read(video).canOpen, true); assert.equal(clicked, 0);
  const result = await context.dom.window.EasyPasteTranscript.collect(video);
  assert.equal(clicked, 1); assert.equal(result.source, "native"); assert.equal(result.cues[0].text, "Test natif");
});
test("native transcript reading refuses search-filtered text and wrong video", async () => {
  const context = page(panel('<input type="search" value="test">' + row("0:00", "Test")), url);
  assert.match((await context.dom.window.EasyPasteTranscript.collect(video)).error, /Effacez la recherche/);
  assert.match((await context.dom.window.EasyPasteTranscript.collect("differentID")).error, /changé/);
});
test("absent transcript never produces an empty successful copy", async () => {
  const context = page("<main>Vidéo sans transcription</main>", url);
  const result = await context.dom.window.EasyPasteTranscript.collect(video);
  assert.match(result.error, /ne propose pas/); assert.equal(result.cues, undefined);
});
test("native collection stops when the user navigates during loading", async () => {
  const context = page('<ytd-video-description-transcript-section-renderer><button>Afficher la transcription</button></ytd-video-description-transcript-section-renderer>', url);
  context.document.querySelector("button").onclick = () => context.dom.reconfigure({ url: "https://www.youtube.com/watch?v=differentID" });
  assert.match((await context.dom.window.EasyPasteTranscript.collect(video)).error, /changé/);
});
test("virtualized transcript collects every row and restores its original scroll position", async () => {
  const context = page(panel('<div id="scroll" style="overflow-y:auto"></div>'), url);
  const scroll = context.document.getElementById("scroll");
  let top = 100;
  const render = () => { const i = Math.min(9, Math.floor(top / 100)); scroll.innerHTML = row(`0:${String(i).padStart(2, "0")}`, `Phrase ${i}`); };
  Object.defineProperties(scroll, {
    clientHeight: { value: 100 }, scrollHeight: { value: 1000 },
    scrollTop: { get: () => top, set: value => { top = value; render(); } }
  });
  render();
  const result = await context.dom.window.EasyPasteTranscript.collect(video);
  assert.equal(result.cues.length, 10); assert.equal(result.cues[0].start, 0); assert.equal(result.cues.at(-1).start, 9); assert.equal(top, 100);
});
test("empty successful HTTP response is classified for native fallback", async () => {
  const context = page("", url); context.dom.window.TextDecoder = TextDecoder;
  context.dom.window.fetch = async () => new Response("  \n ");
  const result = await context.dom.window.eval(`(${readCaptionTrack.toString()})(...${JSON.stringify([`https://www.youtube.com/api/timedtext?v=${video}`, video])})`);
  assert.equal(result.code, "empty"); assert.equal(result.body, undefined);
});
