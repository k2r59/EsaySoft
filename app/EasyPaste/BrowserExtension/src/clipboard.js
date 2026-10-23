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
  const meta = doc.createElement("meta");
  meta.setAttribute("name", "easypaste-source-url");
  if (source) meta.setAttribute("content", source);
  let content = html;
  if (content === undefined) {
    const pre = doc.createElement("pre");
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
