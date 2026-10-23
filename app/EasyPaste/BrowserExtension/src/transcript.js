/* MIT — EasyPaste. Reads the transcript YouTube itself renders, not private APIs. */
(() => {
  "use strict";
  const SEGMENTS = "ytd-transcript-segment-renderer, transcript-segment-view-model";
  const PANELS = "ytd-engagement-panel-section-list-renderer";
  const OPEN_LABEL = /^(?:afficher la transcription|show transcript|mostrar transcripci[oó]n|mostrar transcri[cç][aã]o|transkript anzeigen|mostra trascrizione)$/i;
  const clean = value => String(value || "").replace(/[\u200b\u200e\u200f]/g, "").replace(/\s+/g, " ").trim();

  function checkVideo(expected) {
    const url = new URL(location.href);
    const id = url.pathname === "/watch" ? url.searchParams.get("v") : url.pathname.match(/^\/(?:shorts|live)\/([\w-]{11})(?:\/|$)/)?.[1];
    const rendered = document.querySelector("ytd-watch-flexy[video-id]")?.getAttribute("video-id");
    if (!expected || id !== expected || !["www.youtube.com", "m.youtube.com", "youtube.com"].includes(url.hostname) || (rendered && rendered !== expected)) throw new Error("La vidéo a changé. Fermez puis rouvrez EasyPaste.");
  }
  function visible(element) {
    if (!element || element.closest("[hidden], [aria-hidden='true']") || element.getAttribute("visibility") === "ENGAGEMENT_PANEL_VISIBILITY_HIDDEN") return false;
    const css = getComputedStyle(element);
    return css.display !== "none" && css.visibility !== "hidden";
  }
  function panel() {
    // New YouTube layouts use PAmodern_transcript_view or no stable target-id.
    const candidates = [...document.querySelectorAll(PANELS)].filter(visible);
    return candidates.find(item => item.querySelector(SEGMENTS)) || candidates.find(item => /transcript/i.test(item.getAttribute("target-id") || "")) || null;
  }
  function trigger() {
    const section = document.querySelector("ytd-video-description-transcript-section-renderer");
    const scoped = section?.querySelector("button:not([disabled]), [role='button']:not([aria-disabled='true'])");
    if (scoped) return scoped;
    return [...document.querySelectorAll("ytd-watch-metadata button, #description button, #description [role='button']")].slice(0, 300)
      .find(button => !button.disabled && button.getAttribute("aria-disabled") !== "true" && OPEN_LABEL.test(clean(button.getAttribute("aria-label") || button.textContent))) || null;
  }
  function read(expected) {
    checkVideo(expected);
    const root = panel();
    if (!root) return { cues: [], available: false, canOpen: Boolean(trigger()) };
    const search = root.querySelector("input[type='search'], input#search, input[placeholder], input[aria-label]");
    if (search?.value?.trim()) return { cues: [], available: false, error: "Effacez la recherche dans la transcription YouTube pour copier le texte complet." };
    const nodes = root.querySelectorAll(SEGMENTS);
    if (nodes.length > 12000) return { error: "La transcription dépasse la limite de 12 000 segments." };
    const cues = [];
    let size = 0;
    for (const node of nodes) {
      const timeNode = node.querySelector(".segment-timestamp, .ytwTranscriptSegmentViewModelTimestamp, #timestamp");
      const stamp = clean(timeNode?.textContent);
      if (!/^\d{1,3}:\d{2}(?::\d{2})?$/.test(stamp)) continue;
      const textNode = [...node.querySelectorAll(".segment-text, .ytwTranscriptSegmentViewModelText, span.ytAttributedStringHost[role='text'], .yt-core-attributed-string, span.ytAttributedStringHost")]
        .find(item => item !== timeNode && !timeNode?.contains(item) && !item.closest("[class*='Timestamp']") && clean(item.textContent) !== stamp);
      const text = clean(textNode?.textContent);
      if (!text) continue;
      size += text.length;
      if (size > 500000) return { error: "La transcription dépasse la limite de 500 000 caractères." };
      const start = stamp.split(":").reduce((total, part) => total * 60 + Number(part), 0);
      cues.push({ start, text });
    }
    return { cues, available: cues.length > 0, canOpen: Boolean(trigger()) };
  }
  const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
  async function collect(expected) {
    let scroller = null, initialScroll = 0;
    try {
      checkVideo(expected);
      const initial = read(expected);
      if (initial.error) return initial;
      if (!initial.available) {
        let button = trigger();
        if (!button) {
          const expand = document.querySelector("#description-inline-expander #expand, ytd-watch-metadata #description ytd-text-inline-expander #expand");
          if (expand && visible(expand)) { expand.click(); await pause(150); checkVideo(expected); button = trigger(); }
        }
        if (!button && !panel()) return { error: "YouTube ne propose pas de transcription pour cette vidéo. Aucun texte n’a été copié." };
        if (button) button.click();
      }
      const deadline = performance.now() + 12000;
      let current;
      while (performance.now() < deadline) {
        checkVideo(expected); current = read(expected);
        if (current.error) return current;
        if (current.available) break;
        await pause(150);
      }
      if (!current?.available) return { error: "La transcription YouTube ne s’est pas chargée. Ouvrez-la sur la page, puis réessayez." };
      const root = panel();
      const first = root.querySelector(SEGMENTS);
      // Scroll only the native transcript, to include rows loaded on demand.
      for (let ancestor = first?.parentElement; ancestor && root.contains(ancestor); ancestor = ancestor.parentElement) {
        if (ancestor.clientHeight > 0 && ancestor.scrollHeight > ancestor.clientHeight + 5 && /(auto|scroll)/.test(getComputedStyle(ancestor).overflowY)) { scroller = ancestor; break; }
      }
      const all = new Map();
      let length = 0;
      const merge = snapshot => {
        if (snapshot.error) throw new Error(snapshot.error);
        for (const cue of snapshot.cues || []) {
          const key = `${cue.start}\u0000${cue.text}`;
          if (all.has(key)) continue;
          length += cue.text.length;
          if (all.size >= 12000 || length > 500000) throw new Error("La transcription est trop longue. Aucun extrait incomplet n’a été copié.");
          all.set(key, cue);
        }
      };
      merge(current);
      if (scroller) {
        initialScroll = scroller.scrollTop;
        scroller.scrollTop = 0;
        let settled = 0, previousCount = -1;
        while (performance.now() < deadline) {
          await pause(80); checkVideo(expected);
          merge(read(expected));
          const bottom = scroller.scrollHeight - scroller.clientHeight;
          const reachedBottom = scroller.scrollTop >= bottom - 2;
          if (reachedBottom && all.size === previousCount) settled++; else settled = 0;
          if (settled >= 3) break;
          previousCount = all.size;
          if (!reachedBottom) scroller.scrollTop = Math.min(bottom, scroller.scrollTop + Math.max(100, scroller.clientHeight * 0.85));
        }
        if (settled < 3) return { error: "YouTube charge encore la transcription. Réessayez : aucun extrait incomplet n’a été copié." };
      } else {
        // Let a non-scrolling panel finish its initial asynchronous DOM update too.
        await pause(250); checkVideo(expected); merge(read(expected));
      }
      return { cues: [...all.values()].sort((a, b) => a.start - b.start), source: "native" };
    } catch (error) { return { error: error.message || "Impossible de lire la transcription YouTube." }; }
    finally { if (scroller) scroller.scrollTop = initialScroll; }
  }
  globalThis.EasyPasteTranscript = Object.freeze({ read, collect });
})();
