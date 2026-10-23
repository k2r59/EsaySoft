import { test } from "node:test";
import assert from "node:assert/strict";
import { setDOMParser } from "./helpers.mjs";
import { parseCaptions, normalizeCues, formatTranscript } from "../src/captions.js";
setDOMParser();

test("parses JSON3 including split segments and unicode", () => {
  assert.deepEqual(parseCaptions(JSON.stringify({ events: [{ tStartMs: 1200, segs: [{ utf8: "Bonjour " }, { utf8: "à tous 🎉" }] }, { tStartMs: 4000, segs: [{ utf8: "Suite" }] }] })), [{ start: 1.2, text: "Bonjour à tous 🎉" }, { start: 4, text: "Suite" }]);
});
test("parses YouTube XML transcript and srv3", () => {
  assert.deepEqual(parseCaptions('<transcript><text start="1.25">A &amp; B</text></transcript>'), [{ start: 1.25, text: "A & B" }]);
  assert.deepEqual(parseCaptions('<timedtext><body><p t="2500"><s>Bonjour </s><s>monde</s></p></body></timedtext>'), [{ start: 2.5, text: "Bonjour monde" }]);
});
test("malformed JSON/XML, entities, HTML errors and empty responses fail clearly", () => {
  for (const value of ["", "{broken", '{"events":{}}', '<transcript><text>broken', '<html><body>403</body></html>', '<!DOCTYPE x [<!ENTITY a "evil">]><transcript><text start="0">&a;</text></transcript>', '<transcript/>']) assert.throws(() => parseCaptions(value), /YouTube|lisible|vide/);
});
test("bounds raw response, cue count and plain text length", () => {
  assert.throws(() => parseCaptions(" ".repeat(2000001)), /volumineuse/);
  assert.throws(() => normalizeCues(Array(12001).fill({ start: 0, text: "a" })), /longue/);
  assert.throws(() => normalizeCues([{ start: 0, text: "a".repeat(500001) }]), /longue/);
});
test("preserves repetition, removes only exact event duplicates and invalid timings", () => {
  assert.deepEqual(normalizeCues([{ start: -1, text: "invalid" }, { start: 0, text: "oui" }, { start: 0, text: "oui" }, { start: 1, text: "oui" }, { start: Infinity, text: "invalid" }]), [{ start: 0, text: "oui" }, { start: 1, text: "oui" }]);
});
test("timestamp option supports hour-long videos without HTML interpretation", () => {
  const cues = [{ start: 65.8, text: "<script>alert(1)</script>" }, { start: 3661, text: "Suite" }];
  assert.equal(formatTranscript(cues), "<script>alert(1)</script>\nSuite");
  assert.equal(formatTranscript(cues, { timestamps: true }), "[01:05] <script>alert(1)</script>\n[1:01:01] Suite");
});
