import { test } from "node:test";
import assert from "node:assert/strict";
import { page } from "./helpers.mjs";
import { safeSourceURL, clipboardPayload, writeRichClipboard } from "../src/clipboard.js";

test("source URL accepts only bounded absolute HTTP(S) addresses without credentials", () => {
  assert.equal(safeSourceURL("https://example.test/article?a=1&b=2#section"), "https://example.test/article?a=1&b=2#section");
  assert.equal(safeSourceURL("http://example.test:8080/article"), "http://example.test:8080/article");
  for (const value of [null, "", "/article", "https://user:secret@example.test/", "https://user@example.test/", "javascript:alert(1)", "data:text/html,hi", "file:///tmp/file", "mailto:a@example.test", "https://example.test/\nsecret", `https://example.test/${"a".repeat(8192)}`]) assert.equal(safeSourceURL(value), null);
});
test("metadata attribute serialization preserves the URL without creating injected attributes or visible source text", () => {
  const { document } = page("");
  const url = 'https://example.test/article?q=a&x=%22%3E%3Cscript%3E&y=é#section';
  const result = clipboardPayload({ text: "Texte intact", html: "<p><b>Texte intact</b></p>", sourceURL: url }, document);
  assert.equal(result.text, "Texte intact"); assert.match(result.html, /&amp;/);
  const parsed = new document.defaultView.DOMParser().parseFromString(result.html, "text/html");
  assert.equal(parsed.querySelectorAll("meta").length, 1);
  assert.equal(parsed.querySelector("meta").getAttribute("name"), "easypaste-source-url");
  assert.equal(parsed.querySelector("meta").getAttribute("content"), new URL(url).href);
  assert.equal(parsed.querySelector("meta").attributes.length, 2);
  assert.equal(parsed.body.textContent, "Texte intact"); assert.equal(parsed.querySelector("script"), null);
});
test("plain transcript gains safe HTML while preserving exact plain text and line breaks", () => {
  const { document } = page("");
  const text = '00:02 <script>alert("x")</script> & texte\n00:05 Bonjour éà';
  const result = clipboardPayload({ text, sourceURL: "https://www.youtube.com/watch?v=abcdefghijk" }, document);
  const parsed = new document.defaultView.DOMParser().parseFromString(result.html, "text/html");
  assert.equal(result.text, text); assert.equal(parsed.querySelector("pre").textContent, text);
  assert.equal(parsed.querySelectorAll("script").length, 0); assert.equal(parsed.querySelectorAll("meta").length, 1);
});
test("unsafe source is omitted without changing copied content", () => {
  const { document } = page("");
  const result = clipboardPayload({ text: "Bonjour", sourceURL: "https://name:password@example.test/" }, document);
  assert.equal(result.text, "Bonjour"); assert.doesNotMatch(result.html, /meta|password|name:/);
});
test("final metadata wrapper and escaped transcript obey the UTF-8 HTML budget", () => {
  const { document } = page("");
  assert.throws(() => clipboardPayload({ text: "", html: "a".repeat(2000000), sourceURL: "https://example.test/" }, document), /volumineux/);
  assert.throws(() => clipboardPayload({ text: "&".repeat(500000), sourceURL: "https://example.test/" }, document), /volumineux/);
});
test("payload serialization never creates elements or parses rich markup in the active popup document", () => {
  const { document } = page("<p>Popup intact</p>");
  const before = document.documentElement.outerHTML;
  document.createElement = () => { throw new Error("Do not create content in the popup"); };
  const rich = '<p style="color:rgb(10, 20, 30);font-weight:700">Texte</p>';
  const result = clipboardPayload({ text: "Texte", html: rich, sourceURL: "https://example.test/" }, document);
  assert.ok(result.html.includes(rich));
  assert.match(clipboardPayload({ text: "Une\ntranscription" }, document).html, /<pre style="white-space: pre-wrap;">Une\ntranscription<\/pre>/);
  assert.equal(document.documentElement.outerHTML, before);
});
test("copy event writes exact HTML and plain text once without rendering content or changing the selection", () => {
  const { dom, document } = page('<p id="selected">Sélection du popup</p>');
  const range = document.createRange(); range.selectNodeContents(document.getElementById("selected"));
  dom.window.getSelection().addRange(range);
  const before = document.documentElement.outerHTML, selected = dom.window.getSelection().toString();
  const payload = clipboardPayload({ text: "Gras & couleur", html: '<p style="color:rgb(10, 20, 30)"><b>Gras</b> &amp; couleur</p>', sourceURL: "https://example.test/" }, document);
  const data = {};
  const event = new dom.window.Event("copy", { bubbles: true, cancelable: true });
  Object.defineProperty(event, "clipboardData", { value: { setData: (type, value) => { data[type] = value; } } });
  document.execCommand = command => {
    assert.equal(command, "copy");
    document.dispatchEvent(event);
    return true;
  };
  writeRichClipboard(payload, document);
  assert.equal(event.defaultPrevented, true);
  assert.deepEqual(data, { "text/html": payload.html, "text/plain": payload.text });
  assert.equal(document.documentElement.outerHTML, before);
  assert.equal(dom.window.getSelection().toString(), selected);
  const later = new dom.window.Event("copy", { cancelable: true });
  Object.defineProperty(later, "clipboardData", { value: { setData: () => assert.fail("A later copy must not reuse the payload") } });
  document.dispatchEvent(later);
  assert.equal(later.defaultPrevented, false);
});
test("copy failures are reported and their temporary listener is always removed", () => {
  for (const failure of ["denied", "no-event", "no-data", "write-error", "command-error"]) {
    const { dom, document } = page("");
    document.execCommand = () => {
      if (failure === "denied") return false;
      if (failure === "command-error") throw new Error("Denied");
      if (failure === "no-event") return true;
      const event = new dom.window.Event("copy", { cancelable: true });
      if (failure === "write-error") Object.defineProperty(event, "clipboardData", { value: {
        setData: () => { throw new Error("Write denied"); }, clearData: () => {}
      } });
      document.dispatchEvent(event); return true;
    };
    assert.throws(() => writeRichClipboard({ text: "Essai", html: "<b>Essai</b>" }, document), /refusé la copie/);
    const later = new dom.window.Event("copy", { cancelable: true });
    Object.defineProperty(later, "clipboardData", { value: { setData: () => assert.fail("The failed listener must be removed") } });
    document.dispatchEvent(later);
    assert.equal(later.defaultPrevented, false);
  }
});
