// Functions passed to chrome.scripting must be self-contained (no module closures).
export function inspectYouTube() {
  const current = new URL(location.href);
  if (!["www.youtube.com", "m.youtube.com", "youtube.com"].includes(current.hostname)) return { videoId: null, tracks: [] };
  const videoId = current.pathname === "/watch" ? current.searchParams.get("v") : current.pathname.match(/^\/(?:shorts|live)\/([\w-]{11})(?:\/|$)/)?.[1];
  if (!/^[\w-]{11}$/.test(videoId || "")) return { videoId: null, tracks: [] };
  let response;
  try { response = document.getElementById("movie_player")?.getPlayerResponse?.(); } catch { /* Player not ready. */ }
  if (response?.videoDetails?.videoId !== videoId) response = globalThis.ytInitialPlayerResponse;
  if (response?.videoDetails?.videoId !== videoId) return { videoId, tracks: [], state: "loading" };
  const data = response.captions?.playerCaptionsTracklistRenderer?.captionTracks;
  const tracks = [];
  if (Array.isArray(data)) for (const track of data.slice(0, 100)) {
    try {
      if (typeof track?.baseUrl !== "string" || track.baseUrl.length > 16000) continue;
      const url = new URL(track.baseUrl);
      if (url.protocol !== "https:" || url.origin !== current.origin || url.pathname !== "/api/timedtext" || url.username || url.password || url.href.length > 16000) continue;
      if (url.searchParams.get("v") !== videoId) continue;
      const label = track.name?.simpleText || (Array.isArray(track.name?.runs) ? track.name.runs.slice(0, 30).map(part => String(part?.text || "").slice(0, 150)).join("") : "") || track.languageCode || "Sous-titres";
      tracks.push({ url: url.href, label: String(label).slice(0, 150), language: String(track.languageCode || "").slice(0, 20), automatic: track.kind === "asr" });
    } catch { /* A page-owned value never becomes an arbitrary network request. */ }
  }
  return { videoId, tracks, state: tracks.length ? "available" : "unavailable" };
}

export async function readCaptionTrack(trackURL, expectedVideoId) {
  const page = new URL(location.href);
  const id = page.pathname === "/watch" ? page.searchParams.get("v") : page.pathname.match(/^\/(?:shorts|live)\/([\w-]{11})(?:\/|$)/)?.[1];
  if (id !== expectedVideoId || !["www.youtube.com", "m.youtube.com", "youtube.com"].includes(page.hostname)) return { error: "La vidéo a changé. Fermez puis rouvrez EasyPaste." };
  let url;
  try { url = new URL(trackURL); } catch { return { error: "La piste de sous-titres n’est plus disponible." }; }
  if (url.protocol !== "https:" || url.origin !== page.origin || url.pathname !== "/api/timedtext" || url.searchParams.get("v") !== id || url.username || url.password || url.href.length > 16000) return { error: "L’adresse de la piste de sous-titres n’est pas autorisée." };
  // Use the exact URL provided by the current player, without inventing credentials,
  // changing clients, tokens, signatures, or requesting an inaccessible translation.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10000);
  try {
    const response = await fetch(url.href, { credentials: "include", redirect: "error", signal: controller.signal, cache: "no-store" });
    if (!response.ok) return { error: "YouTube ne donne pas accès à cette piste. Ouvrez sa transcription sur la page, puis réessayez avec « Transcription YouTube »." };
    const size = Number(response.headers.get("Content-Length"));
    if (Number.isFinite(size) && size > 2000000) return { error: "Cette transcription dépasse la limite de 2 Mo." };
    const reader = response.body?.getReader();
    if (!reader) return { error: "YouTube a renvoyé une piste vide.", code: "empty" };
    const decoder = new TextDecoder();
    let body = "", bytes = 0;
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      bytes += value.byteLength;
      if (bytes > 2000000) { await reader.cancel(); return { error: "Cette transcription dépasse la limite de 2 Mo." }; }
      body += decoder.decode(value, { stream: true });
    }
    body += decoder.decode();
    if (!body.trim()) return { error: "YouTube a renvoyé une piste vide.", code: "empty" };
    return { body };
  } catch {
    return { error: "Impossible de lire les sous-titres pour le moment. Ouvrez la transcription dans YouTube, puis utilisez « Transcription YouTube »." };
  } finally { clearTimeout(timer); }
}

export function readDisplayedTranscript(expectedVideoId, probe = false) {
  try {
    const result = globalThis.EasyPasteTranscript.read(expectedVideoId);
    return probe ? { available: result.available, canOpen: result.canOpen, error: result.error } : result;
  } catch (error) { return { error: error.message }; }
}

export async function readNativeTranscript(expectedVideoId) {
  return await globalThis.EasyPasteTranscript.collect(expectedVideoId);
}
