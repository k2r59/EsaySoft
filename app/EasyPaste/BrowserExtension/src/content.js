/* MIT — EasyPaste. Injected only after the user opens the extension. */
(() => {
  "use strict";
  const LIMITS = Object.freeze({ nodes: 8000, text: 500000, html: 2000000, depth: 60, styles: 2000 });
  const TAGS = new Set("article section main div span p h1 h2 h3 h4 h5 h6 strong b em i u s del ins sub sup small mark code pre kbd samp blockquote q ul ol li dl dt dd table thead tbody tfoot tr th td caption a br hr figure figcaption time address".split(" "));
  const DROP = new Set("script style noscript template iframe frame frameset object embed svg math canvas video audio source track link meta base form input textarea select button option datalist dialog nav footer".split(" "));
  const BLOCK = new Set("article section main div p h1 h2 h3 h4 h5 h6 pre blockquote ul ol li dl dt dd table tr caption figure figcaption address hr".split(" "));
  const escape = value => String(value).replace(/[&<>"']/g, char => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[char]));
  const safeLink = (value, base) => {
    try {
      const url = new URL(value, base);
      if (!["https:", "http:", "mailto:"].includes(url.protocol) || url.username || url.password) return null;
      return url.href.length <= 8192 ? url.href : null;
    } catch { return null; }
  };
  const color = value => /^(?:#[\da-f]{3,8}|rgba?\([\d.,%\s]+\)|hsla?\([\d.,%\s]+\)|transparent)$/i.test(value) ? value : null;
  function inlineStyle(style) {
    // Reconstruct a small set of values; no CSS text, custom properties, URLs or positioning.
    const result = [];
    const add = (key, value) => { if (value) result.push(`${key}:${value}`); };
    add("color", color(style.color));
    add("background-color", color(style.backgroundColor));
    if (/^(normal|bold|[1-9]00)$/.test(style.fontWeight)) add("font-weight", style.fontWeight);
    if (/^(normal|italic|oblique)$/.test(style.fontStyle)) add("font-style", style.fontStyle);
    if (/^(underline|line-through|underline line-through)$/.test(style.textDecorationLine)) add("text-decoration", style.textDecorationLine);
    if (/^(left|right|center|justify|start|end)$/.test(style.textAlign)) add("text-align", style.textAlign);
    if (/^(pre|pre-wrap|break-spaces)$/.test(style.whiteSpace)) add("white-space", "pre-wrap");
    const size = parseFloat(style.fontSize);
    if (Number.isFinite(size) && /px$/.test(style.fontSize)) add("font-size", `${Math.max(10, Math.min(size, 48))}px`);
    if (/(monospace|Menlo|Consolas|Courier)/i.test(style.fontFamily)) add("font-family", "monospace");
    return result.join(";");
  }
  function pageInfo(doc = document) {
    const selection = doc.defaultView.getSelection();
    const selected = Boolean(selection && !selection.isCollapsed && selection.rangeCount && selection.toString().trim());
    return { title: doc.title.slice(0, 500), url: doc.location.href, selected };
  }
  function chooseRoot(doc) {
    return doc.querySelector("article") || doc.querySelector("main, [role='main']") || doc.body;
  }
  async function collect({ scope = "page", attribution = true } = {}, doc = document) {
    const info = pageInfo(doc);
    const selection = doc.defaultView.getSelection();
    let range = null;
    let root = chooseRoot(doc);
    if (scope === "selection") {
      if (!info.selected) throw new Error("Sélectionnez d’abord un passage dans la page, puis rouvrez EasyPaste.");
      range = selection.getRangeAt(0).cloneRange();
      root = range.commonAncestorContainer;
      if (root.nodeType === 3) root = root.parentElement;
    }
    if (!root) throw new Error("Cette page ne contient pas de texte à copier.");
    // Reject a selection originating in an editable or hidden control too.
    if (root.closest?.("input, textarea, select, [contenteditable='true'], [hidden], [aria-hidden='true']")) {
      throw new Error("Sélectionnez du texte dans le contenu de la page, hors d’un champ de saisie.");
    }
    let nodes = 0, styles = 0, htmlLength = 0, textLength = 0, sliceStart = performance.now();
    let omittedImages = 0, truncated = false;
    const html = [], plain = [];
    const append = value => { htmlLength += value.length; if (htmlLength > LIMITS.html) { truncated = true; return false; } html.push(value); return true; };
    const newline = () => { if (plain.length && !plain.at(-1).endsWith("\n")) plain.push("\n"); };
    async function visit(node, depth) {
      if (truncated) return;
      if (++nodes > LIMITS.nodes || depth > LIMITS.depth) { truncated = true; return; }
      if (performance.now() - sliceStart > 8) { await new Promise(resolve => setTimeout(resolve, 0)); sliceStart = performance.now(); }
      if (range && !range.intersectsNode(node)) return;
      if (node.nodeType === 3) {
        let value = node.nodeValue || "";
        if (range?.startContainer === node) value = value.slice(range.startOffset, range.endContainer === node ? range.endOffset : undefined);
        else if (range?.endContainer === node) value = value.slice(0, range.endOffset);
        const remaining = LIMITS.text - textLength;
        if (value.length > remaining) { value = value.slice(0, remaining); truncated = true; }
        textLength += value.length; append(escape(value)); plain.push(value); return;
      }
      if (node.nodeType !== 1) return;
      const tag = node.localName.toLowerCase();
      if (DROP.has(tag) || node.namespaceURI !== "http://www.w3.org/1999/xhtml" || node.hidden || node.getAttribute("aria-hidden") === "true" || node.getAttribute("contenteditable") === "true") return;
      let computed;
      if (++styles > LIMITS.styles) { truncated = true; return; }
      computed = doc.defaultView.getComputedStyle(node);
      if (computed.display === "none" || computed.visibility === "hidden" || computed.visibility === "collapse" || computed.opacity === "0") return;
      if (tag === "img") {
        omittedImages++;
        const alt = (node.getAttribute("alt") || "").slice(0, 500);
        if (alt) { append(`<span>[${escape(alt)}]</span>`); plain.push(`[${alt}]`); }
        return;
      }
      const outTag = TAGS.has(tag) ? tag : "div";
      const block = BLOCK.has(outTag);
      if (block) newline();
      if (tag === "li") plain.push("• ");
      let attributes = "";
      if (tag === "a") { const href = safeLink(node.getAttribute("href") || "", info.url); if (href) attributes = ` href="${escape(href)}" rel="noreferrer noopener"`; }
      if (tag === "td" || tag === "th") for (const key of ["colspan", "rowspan"]) {
        const value = Number(node.getAttribute(key)); if (Number.isInteger(value) && value > 1 && value <= 100) attributes += ` ${key}="${value}"`;
      }
      if (tag === "ol") { const start = Number(node.getAttribute("start")); if (Number.isInteger(start) && start > 0 && start < 10000) attributes += ` start="${start}"`; }
      const css = computed ? inlineStyle(computed) : "";
      if (css) attributes += ` style="${escape(css)}"`;
      if (!append(`<${outTag}${attributes}>`)) return;
      if (outTag === "br" || outTag === "hr") { newline(); return; }
      for (const child of node.childNodes) { await visit(child, depth + 1); if (truncated) break; }
      // Closing tags are always emitted, even at the limit, so the fragment stays well formed.
      html.push(`</${outTag}>`);
      if (block) newline();
      else if (outTag === "td" || outTag === "th") plain.push("\t");
    }
    await visit(root, 0);
    if (truncated) throw new Error("Ce contenu est trop volumineux. Sélectionnez un passage plus court : aucune copie partielle n’a été faite.");
    let text = plain.join("").replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
    if (!text) throw new Error("Aucun texte lisible à copier. Les images seules, PDF et contenus intégrés ne sont pas pris en charge.");
    if (attribution) {
      const href = safeLink(info.url, info.url);
      if (href) { html.push(`<p>Source : <a href="${escape(href)}" rel="noreferrer noopener">${escape(info.title || href)}</a></p>`); text += `\n\nSource : ${info.title}\n${href}`; }
    }
    // A white paragraph on a dark site must not become white-on-white when pasted.
    let background = "rgb(255, 255, 255)";
    for (let ancestor = root; ancestor?.nodeType === 1; ancestor = ancestor.parentElement) {
      const candidate = doc.defaultView.getComputedStyle(ancestor).backgroundColor;
      if (candidate && candidate !== "transparent" && !/^rgba\([^)]*,\s*0\s*\)$/.test(candidate) && color(candidate)) { background = candidate; break; }
    }
    const rich = `<div style="background-color:${escape(background)}">${html.join("")}</div>`;
    if (new Blob([rich]).size > LIMITS.html) throw new Error("Ce contenu est trop volumineux. Sélectionnez un passage plus court : aucune copie partielle n’a été faite.");
    return { html: rich, text, title: info.title, scope, omittedImages };
  }
  globalThis.EasyPasteWeb = Object.freeze({ collect, pageInfo, safeLink, inlineStyle, LIMITS });
})();
