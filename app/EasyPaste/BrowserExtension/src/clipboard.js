/* MIT — EasyPaste. Source metadata never changes the visible copied text. */
export function safeSourceURL(value) {
  if (typeof value !== "string" || value.length > 8192 || /[\u0000-\u0020\u007f]/.test(value)) return null;
  try {
    const url = new URL(value);
    if (!["https:", "http:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.href.length > 8192) return null;
    return url.href;
  } catch { return null; }
}

export function clipboardPayload({ text, html, sourceURL }, doc = document) {
  const source = safeSourceURL(sourceURL);
  // Serialize metadata and transcript text in a document with no browsing context.
  const inert = doc.implementation.createHTMLDocument("");
  const meta = inert.createElement("meta");
  meta.setAttribute("name", "easypaste-source-url");
  if (source) meta.setAttribute("content", source);
  let content = html;
  if (content === undefined) {
    const pre = inert.createElement("pre");
    pre.style.whiteSpace = "pre-wrap";
    pre.textContent = text;
    content = pre.outerHTML;
  }
  // Only locally sanitized page HTML or the text-only <pre> above reaches here.
  // Attribute serialization comes from the DOM, never raw URL interpolation.
  const rich = `<!doctype html><html><head>${source ? meta.outerHTML : ""}</head><body>${content}</body></html>`;
  if (new Blob([rich]).size > 2000000) throw new Error("Ce contenu est trop volumineux. Sélectionnez un passage plus court : aucune copie partielle n’a été faite.");
  return { text, html: rich };
}

export function writeRichClipboard({ text, html }, doc = document) {
  const failure = "Le navigateur a refusé la copie. Gardez cette fenêtre ouverte, puis réessayez.";
  if (typeof text !== "string" || typeof html !== "string" || typeof doc.execCommand !== "function") throw new Error(failure);
  let handled = false, failed = false;
  const copy = event => {
    if (handled || !event.clipboardData) return;
    // Supply inert strings directly: never insert page markup or change selection.
    // Chromium's async HTML writer parses styles against the popup CSP, even for
    // detached markup. The copy event preserves both formats without that parse.
    event.preventDefault();
    event.stopImmediatePropagation();
    try {
      event.clipboardData.setData("text/html", html);
      event.clipboardData.setData("text/plain", text);
      handled = true;
    } catch {
      failed = true;
      try { event.clipboardData.clearData(); } catch { /* Report the failed write below. */ }
    }
  };
  doc.addEventListener("copy", copy, true);
  try {
    if (!doc.execCommand("copy") || !handled || failed) throw new Error(failure);
  } catch { throw new Error(failure); }
  finally { doc.removeEventListener("copy", copy, true); }
}
