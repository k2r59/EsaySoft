// Adapted from the user-supplied youtube-sous-titres archive (direct.js / extract.js).
// Self-contained functions: Chrome serializes them into the active YouTube page.
export async function youtubeDirect(operation, expectedId, selected) {
  const origin = 'https://www.youtube.com';
  function assertVideo() {
    const u = new URL(location.href);
    const id = u.pathname === '/watch' ? u.searchParams.get('v') : u.pathname.match(/^\/(?:shorts|live)\/([\w-]{11})(?:\/|$)/)?.[1];
    if (u.protocol !== 'https:' || !['www.youtube.com', 'youtube.com', 'm.youtube.com'].includes(u.hostname) || !/^[\w-]{11}$/.test(expectedId) || id !== expectedId) throw new Error('La vidéo a changé. Fermez puis rouvrez EasyPaste.');
  }
  async function request(url, limit, options = {}) {
    assertVideo();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch(url, { ...options, credentials: 'omit', redirect: 'error', cache: 'no-store', signal: controller.signal });
      if (!response.ok) throw new Error(`YouTube a refusé la récupération (HTTP ${response.status}).`);
      if (Number(response.headers.get('content-length')) > limit) throw new Error('La réponse YouTube est trop volumineuse.');
      const reader = response.body?.getReader();
      if (!reader) throw new Error('YouTube a renvoyé une piste vide.');
      const decoder = new TextDecoder();
      let text = '', bytes = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        bytes += value.byteLength;
        if (bytes > limit) { await reader.cancel(); throw new Error('La réponse YouTube est trop volumineuse.'); }
        text += decoder.decode(value, { stream: true });
      }
      text += decoder.decode();
      assertVideo();
      return text;
    } finally { clearTimeout(timer); }
  }
  function captionURL(track) {
    const url = new URL(track.url);
    if (url.origin !== origin || url.username || url.password || url.href.length > 16000 || url.pathname !== '/api/timedtext' || url.searchParams.get('v') !== expectedId || url.searchParams.get('lang') !== track.language || (url.searchParams.get('kind') || '') !== track.kind || url.searchParams.has('tlang')) throw new Error('La piste reçue ne correspond pas à la vidéo et à la langue choisies.');
    return url;
  }
  try {
    assertVideo();
    const html = await request(`${origin}/watch?v=${expectedId}&hl=en`, 8000000);
    const match = html.match(/"VISITOR_DATA"\s*:\s*("(?:\\.|[^"\\])*")/) || html.match(/"visitorData"\s*:\s*("(?:\\.|[^"\\])*")/);
    if (!match) throw new Error('YouTube ne fournit pas le contexte nécessaire aux sous-titres.');
    const visitor = JSON.parse(match[1]);
    if (typeof visitor !== 'string' || !visitor.length || visitor.length > 16000 || /[\r\n]/.test(visitor)) throw new Error('Contexte YouTube invalide.');
    const player = JSON.parse(await request(`${origin}/youtubei/v1/player?prettyPrint=false`, 2000000, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-YouTube-Client-Name': '101', 'X-YouTube-Client-Version': '1.02', 'X-Goog-Visitor-Id': visitor },
      body: JSON.stringify({ context: { client: {
        clientName: 'VISIONOS', clientVersion: '1.02', deviceMake: 'Apple', deviceModel: 'RealityDevice17,1',
        osName: 'visionOS', osVersion: '26.5.23O471', hl: 'en', timeZone: 'UTC', utcOffsetMinutes: 0
      } }, videoId: expectedId, contentCheckOk: true, racyCheckOk: true })
    }));
    if (player.videoDetails?.videoId !== expectedId) throw new Error('YouTube ne rend pas les pistes de cette vidéo accessibles.');
    const raw = player.captions?.playerCaptionsTracklistRenderer?.captionTracks;
    const tracks = [];
    if (Array.isArray(raw)) for (const t of raw.slice(0, 100)) {
      const track = { url: t.baseUrl, language: String(t.languageCode || '').slice(0, 20), kind: t.kind || '', automatic: t.kind === 'asr', label: String(t.name?.simpleText || t.name?.runs?.map(r => r.text).join('') || t.languageCode || 'Sous-titres').slice(0, 150) };
      try { captionURL(track); tracks.push(track); } catch { /* Reject page-owned arbitrary URLs. */ }
    }
    if (operation === 'list') return { videoId: expectedId, tracks };
    if (operation !== 'read' || !selected) throw new Error('Choisissez une piste de sous-titres.');
    const kind = selected.automatic ? 'asr' : (selected.kind || '');
    const track = tracks.find(t => t.language === selected.language && t.kind === kind);
    if (!track) throw new Error('La piste choisie n’est plus disponible. Actualisez les pistes.');
    const url = captionURL(track); url.searchParams.set('fmt', 'json3');
    const body = await request(url.href, 2000000);
    if (!body.trim()) throw new Error('YouTube a renvoyé une piste vide.');
    return { body, videoId: expectedId };
  } catch (error) {
    return { error: `${error?.name === 'AbortError' ? 'YouTube met trop de temps à répondre.' : error?.message || 'Impossible de joindre YouTube.'} Vous pouvez aussi choisir « Transcription YouTube ».` };
  }
}

// Read the complete model of the new virtualized transcript, rather than only
// the handful of rows currently rendered. The older DOM reader remains a fallback.
export async function readTranscriptModel(expectedId, open = false) {
  function assertVideo() {
    const u = new URL(location.href);
    const id = u.pathname === '/watch' ? u.searchParams.get('v') : u.pathname.match(/^\/(?:shorts|live)\/([\w-]{11})(?:\/|$)/)?.[1];
    const watchId = document.querySelector('ytd-watch-flexy')?.getAttribute('video-id');
    if (u.protocol !== 'https:' || !['www.youtube.com', 'm.youtube.com', 'youtube.com'].includes(u.hostname) || !/^[\w-]{11}$/.test(expectedId) || id !== expectedId || (watchId && watchId !== expectedId)) throw new Error('La vidéo a changé. Fermez puis rouvrez EasyPaste.');
  }
  function read() {
    assertVideo();
    const panels = [...document.querySelectorAll('ytd-engagement-panel-section-list-renderer')];
    const panel = panels.find(p => p.getAttribute('visibility') === 'ENGAGEMENT_PANEL_VISIBILITY_EXPANDED' && !p.hidden && p.getAttribute('aria-hidden') !== 'true' && getComputedStyle(p).display !== 'none' && getComputedStyle(p).visibility !== 'hidden' && (/transcript/.test(p.getAttribute('target-id') || '') || p.data?.identifier?.tag === 'engagement-panel-timeline-view-consolidated'));
    if (!panel) return [];
    if ([...panel.querySelectorAll('input')].some(i => i.value?.trim())) throw new Error('Effacez la recherche dans la transcription YouTube pour récupérer le texte complet.');
    const pending = [panel.data?.content], visited = new WeakSet(), cues = [];
    let nodes = 0, characters = 0;
    while (pending.length) {
      const value = pending.pop();
      if (!value || typeof value !== 'object' || visited.has(value)) continue;
      visited.add(value);
      if (++nodes > 100000) throw new Error('La transcription est trop volumineuse.');
      const row = value.transcriptSegmentViewModel;
      if (row && typeof row.simpleText === 'string' && typeof row.timestamp === 'string' && /^(?:\d+:)?\d{1,2}:[0-5]\d$/.test(row.timestamp.trim())) {
        const text = row.simpleText.replace(/[\u200B\uFEFF]/g, '').replace(/\s+/g, ' ').trim();
        characters += text.length;
        if (characters > 500000 || cues.length >= 12000) throw new Error('La transcription est trop volumineuse.');
        if (text) cues.push({ start: row.timestamp.trim().split(':').reduce((sum, part) => sum * 60 + Number(part), 0), text });
      }
      const children = Object.values(value);
      if (children.length + pending.length > 100000) throw new Error('La transcription est trop volumineuse.');
      // Reverse push preserves source order, including equal-timestamp segments.
      for (let i = children.length - 1; i >= 0; i--) if (children[i] && typeof children[i] === 'object') pending.push(children[i]);
    }
    return cues;
  }
  try {
    let cues = read();
    if (!cues.length && open) {
      document.querySelector('ytd-watch-metadata #description-inline-expander #expand')?.click();
      const button = document.querySelector('ytd-video-description-transcript-section-renderer button, ytd-video-description-transcript-section-renderer [role="button"]');
      button?.click();
      for (let i = 0; i < 4 && !cues.length; i++) { await new Promise(r => setTimeout(r, 250)); cues = read(); }
    }
    assertVideo();
    return { cues };
  } catch (error) { return { error: error.message }; }
}
