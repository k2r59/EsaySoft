import { test } from "node:test";
import assert from "node:assert/strict";
import { performance } from "node:perf_hooks";
import { page } from "./helpers.mjs";

test("preserves headings, emphasis, lists, tables and absolute links", async () => {
  const { api } = page('<main><h1>Titre</h1><p>Du <strong>gras</strong> et <em>italique</em>.</p><ul><li>Premier</li><li>Deuxième</li></ul><table><tr><th>Nom</th><td colspan="2">Valeur</td></tr></table><a href="/suite">Suite</a></main>');
  const result = await api.collect({ attribution: false });
  assert.match(result.html, /<h1[^>]*>Titre<\/h1>/);
  assert.match(result.html, /<strong[^>]*>gras/);
  assert.match(result.html, /<em[^>]*>italique/);
  assert.match(result.html, /colspan="2"/);
  assert.match(result.html, /href="https:\/\/example.test\/suite"/);
  assert.match(result.text, /• Premier\n• Deuxième/);
  assert.match(result.text, /Nom\tValeur/);
});

test("rejects active HTML, SVG, events, forms, frames and external resources", async () => {
  const { api } = page('<article onmouseover="evil()"><h2>Valide</h2><script>secret()</script><style>@import "https://evil.test"</style><iframe src="https://evil.test">caché</iframe><object data="evil">caché</object><svg><foreignObject>caché</foreignObject></svg><math><mtext>caché</mtext></math><form><input value="motdepasse"><p>Secret formulaire</p></form><img src="https://evil.test/pixel" onerror="evil()" alt="Illustration"><p style="background-image:url(https://evil.test/x);position:fixed">Texte</p></article>');
  const result = await api.collect({ attribution: false });
  assert.doesNotMatch(result.html, /<(?:script|style|iframe|object|svg|math|form|input|img)\b/i);
  assert.doesNotMatch(result.html, /onmouseover|onerror|evil|position:|background-image/);
  assert.doesNotMatch(result.text, /secret|motdepasse|caché/i);
  assert.equal(result.omittedImages, 1);
  assert.match(result.text, /Illustration/);
});

test("blocks malicious protocols and attribute escape injection", async () => {
  const { api } = page('<main><a href="javascript:alert(1)">A</a><a href="jAvAsCrIpT:evil()">B</a><a href="data:text/html,evil">C</a><a href="file:///etc/passwd">D</a><a href="https://user:pass@evil.test/">E</a><a href="https://safe.test/?q=&quot; onclick=&quot;evil()">F</a></main>');
  const result = await api.collect({ attribution: false });
  const parsed = page(result.html).document;
  for (const anchor of [...parsed.querySelectorAll("a")].slice(0, 5)) assert.equal(anchor.hasAttribute("href"), false);
  assert.equal(parsed.querySelector("[onclick]"), null);
  assert.equal(parsed.querySelectorAll("a[href]").length, 1);
});

test("never includes controls or hidden content", async () => {
  const { api } = page('<article><p>Visible</p><p hidden>Secret1</p><p aria-hidden="true">Secret2</p><p style="display:none">Secret3</p><p style="opacity:0">Secret4</p><div contenteditable="true">Secret5</div></article>');
  assert.equal((await api.collect({ attribution: false })).text, "Visible");
});

test("copies only the selected text boundaries and formatting", async () => {
  const { api, document, dom } = page('<article><p>AVANT <b>bonjour monde</b> APRÈS</p><p>HORS SÉLECTION</p></article>');
  const node = document.querySelector("b").firstChild;
  const range = document.createRange(); range.setStart(node, 0); range.setEnd(node, 7);
  dom.window.getSelection().addRange(range);
  assert.equal(api.pageInfo().selected, true);
  const result = await api.collect({ scope: "selection", attribution: false });
  assert.equal(result.text, "bonjour");
  assert.match(result.html, /<b[^>]*>bonjour<\/b>/);
  assert.doesNotMatch(result.html, /AVANT|APRÈS|HORS/);
});

test("rejects absent selection and refuses partial copies", async () => {
  const { api } = page('<article><p>Bonjour</p></article>');
  await assert.rejects(api.collect({ scope: "selection" }), /Sélectionnez/);
  const huge = page(`<article>${"A".repeat(500001)}</article>`);
  await assert.rejects(huge.api.collect(), /volumineux/);
});

test("bounds depth and number of styled elements", async () => {
  await assert.rejects(page('<div>'.repeat(65) + 'Texte' + '</div>'.repeat(65)).api.collect(), /volumineux/);
  await assert.rejects(page('<article>' + '<span>A</span>'.repeat(2100) + '</article>').api.collect(), /volumineux/);
});

test("does not obey attacker-controlled base URLs", async () => {
  const { api } = page('<base href="https://evil.test/"><article><a href="relative">Texte</a></article>');
  const result = await api.collect();
  assert.match(result.html, /https:\/\/example.test\/relative/);
  assert.doesNotMatch(result.html, /evil/);
  assert.match(result.text, /Source : Article d’essai/);
});

test("preserves dark-page text contrast in the rich fragment", async () => {
  const { api, document } = page('<article><p>Texte blanc</p></article>');
  document.body.style.cssText = "background-color:rgb(15, 20, 25);color:rgb(250,250,250)";
  const result = await api.collect({ attribution: false });
  assert.match(result.html, /background-color:rgb\(15, 20, 25\)/);
  assert.match(result.html, /color:rgb\(250, 250, 250\)/);
});

test("large article yields between chunks and stays bounded", async context => {
  const { api } = page('<article><h1>Performance</h1>' + '<p>Un paragraphe de texte avec <b>du gras</b> et un <a href="/lien">lien</a>.</p>'.repeat(220) + '</article>');
  let ticks = 0; const timer = setInterval(() => ticks++, 1); const start = performance.now();
  const result = await api.collect({ attribution: false }); clearInterval(timer);
  const elapsed = performance.now() - start;
  assert.ok(ticks > 0, "the event loop must get opportunities to paint");
  assert.ok(result.html.length < api.LIMITS.html);
  assert.ok(elapsed < 5000, `unexpected CPU regression: ${elapsed} ms`);
  context.diagnostic(`220 paragraphs: ${Math.round(elapsed)} ms in jsdom, ${ticks} event-loop yields`);
});

test("CSS allowlist never accepts URLs, expressions or injected declarations", () => {
  const { api } = page("test");
  const result = api.inlineStyle({ color: "red;position:fixed", backgroundColor: "url(https://evil.test)", fontWeight: "expression(evil())", fontSize: "16px;bad:yes", fontFamily: "evil()", textAlign: "center;bad:yes" });
  assert.equal(result, "");
});

test("the final HTML limit is checked in UTF-8 bytes, including multibyte text", async () => {
  const link = `<a href="https://example.test/${"x".repeat(7000)}">Lien</a>`;
  const { api } = page(`<article>${"漢".repeat(250000)}${link.repeat(200)}</article>`);
  await assert.rejects(api.collect({ attribution: false }), /volumineux/);
});
