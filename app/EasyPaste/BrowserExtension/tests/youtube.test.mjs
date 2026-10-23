import { test } from "node:test";
import assert from "node:assert/strict";
import { page } from "./helpers.mjs";
import { inspectYouTube, readCaptionTrack, readDisplayedTranscript } from "../src/youtube.js";

const video = "abcdefghijk", url = `https://www.youtube.com/watch?v=${video}`;
const trackURL = `https://www.youtube.com/api/timedtext?v=${video}&lang=fr&signature=provided`;
const track = { baseUrl: trackURL, name: { simpleText: "Français" }, languageCode: "fr", kind: "asr" };
function player(tracks = [track], id = video, pageURL = url) {
  const context = page('<div id="movie_player"></div>', pageURL);
  context.dom.window.document.getElementById("movie_player").getPlayerResponse = () => ({ videoDetails: { videoId: id }, captions: { playerCaptionsTracklistRenderer: { captionTracks: tracks } } });
  return context;
}
const call = (context, fn, args = []) => context.dom.window.eval(`(${fn.toString()})(...${JSON.stringify(args)})`);

test("detects the current player, language and automatic captions", () => {
  const result = call(player(), inspectYouTube);
  assert.equal(result.videoId, video); assert.equal(result.state, "available");
  assert.equal(result.tracks[0].label, "Français"); assert.equal(result.tracks[0].automatic, true);
});
test("does not reuse stale player state after SPA navigation", () => {
  const context = player([track], "staleplayer");
  context.dom.window.ytInitialPlayerResponse = { videoDetails: { videoId: "staleplayer" }, captions: { playerCaptionsTracklistRenderer: { captionTracks: [track] } } };
  assert.equal(call(context, inspectYouTube).tracks.length, 0);
  assert.equal(call(context, inspectYouTube).state, "loading");
});
test("supports video routes and rejects lookalike domains", () => {
  for (const path of [`/watch?v=${video}`, `/shorts/${video}`, `/live/${video}`]) assert.equal(call(player([track], video, `https://www.youtube.com${path}`), inspectYouTube).videoId, video);
  assert.equal(call(page("", "https://youtube.com.evil.test/watch?v=abcdefghijk"), inspectYouTube).videoId, null);
  assert.equal(call(page("", "https://www.youtube.com/results?search_query=x"), inspectYouTube).videoId, null);
});
test("filters dangerous, third-party and wrong-video URLs", () => {
  const bad = ["javascript:alert(1)", "https://evil.test/api/timedtext?v=abcdefghijk", "https://www.youtube.com/redirect?v=abcdefghijk", "https://www.youtube.com/api/timedtext?v=other-video", "https://user:pass@www.youtube.com/api/timedtext?v=abcdefghijk", "http://www.youtube.com/api/timedtext?v=abcdefghijk"];
  const result = call(player([...bad.map(baseUrl => ({ ...track, baseUrl })), track]), inspectYouTube);
  assert.equal(result.tracks.length, 1); assert.equal(result.tracks[0].url, trackURL);
});
test("downloads the exact existing track, with redirect denial and a bounded stream", async () => {
  const context = player(); let requested;
  context.dom.window.fetch = async (address, options) => { requested = { address, options }; return new Response('<transcript><text start="1">Bonjour</text></transcript>'); };
  context.dom.window.TextDecoder = TextDecoder;
  const result = await call(context, readCaptionTrack, [trackURL, video]);
  assert.match(result.body, /Bonjour/); assert.equal(requested.address, trackURL);
  assert.equal(requested.options.redirect, "error"); assert.equal(requested.options.credentials, "include");
});
test("denies arbitrary URLs before performing any network request", async () => {
  const context = player(); let count = 0; context.dom.window.fetch = async () => { count++; throw new Error(); };
  for (const address of ["https://evil.test/", "file:///tmp/secret", `https://www.youtube.com/api/timedtext?v=wrongvideo1`]) assert.match((await call(context, readCaptionTrack, [address, video])).error, /autorisée/);
  assert.match((await call(context, readCaptionTrack, [trackURL, "other"])).error, /changé/);
  assert.equal(count, 0);
});
test("forbidden, offline and oversized responses produce safe errors", async () => {
  const context = player(); context.dom.window.TextDecoder = TextDecoder;
  context.dom.window.fetch = async () => new Response("Forbidden", { status: 403 });
  assert.match((await call(context, readCaptionTrack, [trackURL, video])).error, /pas accès/);
  context.dom.window.fetch = async () => { throw new TypeError("Network Error with secret URL"); };
  assert.doesNotMatch((await call(context, readCaptionTrack, [trackURL, video])).error, /secret/);
  context.dom.window.fetch = async () => new Response("a".repeat(2000001));
  assert.match((await call(context, readCaptionTrack, [trackURL, video])).error, /limite/);
});
test("reads only the displayed native transcript and detects its absence", () => {
  const context = page('<ytd-engagement-panel-section-list-renderer target-id="engagement-panel-searchable-transcript" visibility="ENGAGEMENT_PANEL_VISIBILITY_EXPANDED"><ytd-transcript-segment-renderer><span class="segment-timestamp">1:05</span><span class="segment-text">Bonjour</span></ytd-transcript-segment-renderer></ytd-engagement-panel-section-list-renderer>', url);
  assert.equal(call(context, readDisplayedTranscript, [video]).cues[0].start, 65);
  context.document.querySelector("ytd-engagement-panel-section-list-renderer").setAttribute("visibility", "ENGAGEMENT_PANEL_VISIBILITY_HIDDEN");
  assert.equal(call(context, readDisplayedTranscript, [video]).cues.length, 0);
});
