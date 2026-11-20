import { helloRequest, NATIVE_HOST, nativeFailure } from './native.js';

export function detectPageMedia() {
  const candidates = [], seen = new Set();
  function add(raw, label) {
    try {
      const u = new URL(raw, location.href);
      if (!raw || !['https:', 'http:'].includes(u.protocol) || u.username || u.password || u.href.length > 2048 || seen.has(u.href)) return;
      seen.add(u.href); candidates.push({ url: u.href, label });
    } catch { /* Unsupported embedded resources remain handled by the page extractor. */ }
  }
  add(location.href, 'Page actuelle');
  for (const el of [...document.querySelectorAll('video, audio')].slice(0, 20)) {
    const label = el.tagName === 'AUDIO' ? 'Audio détecté' : 'Vidéo détectée';
    add(el.currentSrc || el.getAttribute('src'), label);
    for (const source of [...el.querySelectorAll('source')].slice(0, 5)) add(source.getAttribute('src'), label);
  }
  for (const meta of [...document.querySelectorAll('meta[property="og:video"], meta[property="og:video:url"], meta[property="og:audio"]')].slice(0, 10)) add(meta.content, 'Média déclaré par la page');
  return { pageURL: location.href, detected: !!document.querySelector('video, audio') || candidates.length > 1, candidates: candidates.slice(0, 20) };
}

export function mediaRequest(version, url, mode, cryptoAPI = crypto, quality) {
  const parsed = new URL(url);
  if (!['video', 'audio'].includes(mode) || !['https:', 'http:'].includes(parsed.protocol) || parsed.username || parsed.password || url.length > 2048) throw new Error('Choisissez une source vidéo ou audio valide.');
  if (quality !== undefined && !['best','1080','720','480'].includes(quality)) throw new Error('Qualité vidéo invalide.');
  return { ...helloRequest(version, cryptoAPI), type: 'media', mode, url: parsed.href, ...(quality ? { quality } : {}) };
}
export async function sendMediaRequest(api, request, timeoutMs = 8000) {
  let timer;
  try {
    const reply = await Promise.race([
      api.runtime.sendNativeMessage(NATIVE_HOST, request).catch(error => { throw new Error(`${nativeFailure(error)} Le téléchargement nécessite la nouvelle version d’EasyPaste.`); }),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('EasyPaste ne répond pas. Vérifiez la fenêtre Téléchargements web avant de réessayer.')), timeoutMs); })
    ]);
    if (!reply || reply.protocol !== 1 || reply.type !== 'media' || reply.nonce !== request.nonce || !['queued', 'disabled', 'error'].includes(reply.status) || Object.keys(reply).some(k => !['protocol', 'type', 'nonce', 'status', 'message', 'jobID'].includes(k)) || (reply.message !== undefined && (typeof reply.message !== 'string' || reply.message.length > 240))) throw new Error('Mettez à jour EasyPaste pour utiliser les téléchargements vidéo et audio.');
    if (reply.jobID !== undefined && !isJobID(reply.jobID)) throw new Error('Réponse de téléchargement non valide.');
    if (reply.status !== 'queued') throw new Error(reply.message || 'Activez la connexion dans EasyPaste → Réglages → Intégrations.');
    return reply;
  } finally { clearTimeout(timer); }
}


const isJobID = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
export async function mediaStatus(api, jobID, options = {}) {
  if (!isJobID(jobID)) throw new Error('Identifiant de téléchargement invalide.');
  const request = { ...helloRequest(api.runtime.getManifest().version, options.cryptoAPI), type: 'mediaStatus', jobID };
  let timer;
  try {
    const reply = await Promise.race([
      api.runtime.sendNativeMessage(NATIVE_HOST, request),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Le suivi ne répond pas. Vérifiez EasyPaste.')), options.timeoutMs ?? 8000); })
    ]);
    if (!reply || reply.protocol !== 1 || reply.type !== 'mediaStatus' || reply.nonce !== request.nonce || reply.jobID?.toLowerCase() !== jobID.toLowerCase() ||
        !['queued', 'preparing', 'downloading', 'completed', 'cancelled', 'error', 'unknown'].includes(reply.status) ||
        typeof reply.message !== 'string' || reply.message.length > 240 ||
        Object.keys(reply).some(k => !['protocol', 'type', 'nonce', 'jobID', 'status', 'message'].includes(k))) throw new Error('Suivi indisponible. Vérifiez les téléchargements dans EasyPaste.');
    return reply;
  } finally { clearTimeout(timer); }
}

export function mountMediaCard(doc = document, api = chrome, options = {}) {
  const $ = id => doc.getElementById(id);
  const card = $('media-card'), sources = $('media-source'), status = $('media-status');
  const video = $('download-video'), audio = $('download-audio'), start = $('download-start');
  let tabId, pageURL, candidates = [], busy = false, mode = 'video', timer, stopped = false;
  const storage = options.storage ?? doc.defaultView?.localStorage;
  const key = 'easypaste-latest-download';
  const labels = { queued: 'En attente…', preparing: 'Préparation…', downloading: 'Téléchargement en cours', completed: 'Téléchargement terminé', cancelled: 'Téléchargement annulé', error: 'Téléchargement impossible', unknown: 'Vérifier dans EasyPaste' };
  function report(text, state = 'queued') {
    $('download-progress').hidden = false;
    $('download-progress').dataset.state = state;
    $('download-state').textContent = labels[state] || labels.queued;
    status.textContent = text; status.dataset.kind = state === 'completed' ? 'success' : ['error', 'unknown'].includes(state) ? 'error' : 'info';
    if (!$('download-screen').hidden) $('download-progress').scrollIntoView?.({ block: 'nearest' });
    const path = $('download-progress').querySelector('.progress-symbol svg');
    path.innerHTML = state === 'completed' ? '<path d="m5 12 4 4L19 6"/>' : state === 'error' || state === 'cancelled' || state === 'unknown' ? '<circle cx="12" cy="12" r="9"/><path d="M12 7v6m0 4h.01"/>' : '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>';
  }
  function controls(value) { busy = value; start.disabled = value || !candidates.length; video.disabled = audio.disabled = sources.disabled = $('media-quality').disabled = value; }
  function selectMode(value) {
    mode = value; video.setAttribute('aria-pressed', String(mode === 'video')); audio.setAttribute('aria-pressed', String(mode === 'audio'));
    start.querySelector('span').textContent = mode === 'video' ? 'Télécharger la vidéo' : 'Télécharger l’audio';
    $('quality-row').hidden = mode === 'audio';
  }
  video.addEventListener('click', () => selectMode('video'));
  audio.addEventListener('click', () => selectMode('audio'));
  async function poll(job) {
    clearTimeout(timer);
    if (stopped) return;
    try {
      const reply = await mediaStatus(api, job.id, options);
      if (stopped) return;
      report(reply.message, reply.status);
      const active = ['queued', 'preparing', 'downloading'].includes(reply.status);
      controls(active);
      if (active) timer = setTimeout(() => poll(job), options.pollMs ?? 1500);
    } catch {
      if (!stopped) { report('Ouvrez Téléchargements web dans EasyPaste pour vérifier le résultat.', 'unknown'); controls(false); }
    }
  }
  doc.defaultView?.addEventListener('pagehide', () => { stopped = true; clearTimeout(timer); }, { once: true });
  async function inspect() {
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !/^https?:\/\//.test(tab.url || '')) return;
    tabId = tab.id;
    const results = await api.scripting.executeScript({ target: { tabId }, func: detectPageMedia });
    const result = results.find(r => r.frameId === 0)?.result;
    if (!result?.candidates?.length) return;
    pageURL = result.pageURL; candidates = result.candidates;
    sources.replaceChildren();
    candidates.forEach((c, index) => { const option = doc.createElement('option'); option.value = String(index); option.textContent = `${c.label}${index ? ' · ' + new URL(c.url).hostname : ''}`; sources.add(option); });
    $('media-source-options').hidden = candidates.length <= 1;
    card.hidden = false; $('nav-download').disabled = false; controls(false);
    const u = new URL(pageURL);
    if (['www.youtube.com', 'm.youtube.com', 'youtube.com'].includes(u.hostname)) {
      const id = u.searchParams.get('v');
      if (/^[a-zA-Z0-9_-]{11}$/.test(id || '')) {
        const img = $('media-thumbnail');
        img.addEventListener('load', () => { img.hidden = false; $('media-placeholder').hidden = true; });
        img.src = `https://i.ytimg.com/vi/${id}/mqdefault.jpg`;
      }
    }
    try {
      const job = JSON.parse(storage?.getItem(key) || 'null');
      if (isJobID(job?.id) && ['video', 'audio'].includes(job.mode) && Date.now() - job.created < 86400000) {
        selectMode(job.mode); controls(true); report('Vérification du dernier téléchargement…', 'preparing'); await poll(job);
      }
    } catch { /* Storage can be unavailable; an explicit download still works. */ }
  }
  start.addEventListener('click', async () => {
    if (busy || !candidates.length) return;
    let permission;
    try { permission = api.permissions.request({ permissions: ['nativeMessaging'] }); }
    catch { report('Connectez l’extension à EasyPaste depuis les réglages.', 'error'); return; }
    controls(true); clearTimeout(timer); report('Envoi à EasyPaste…', 'preparing');
    try {
      if (!await permission) throw new Error('La connexion à EasyPaste est nécessaire pour télécharger.');
      const results = await api.scripting.executeScript({ target: { tabId }, func: () => location.href });
      if (results.find(r => r.frameId === 0)?.result !== pageURL) throw new Error('La page a changé. Fermez puis rouvrez l’extension.');
      const request = mediaRequest(api.runtime.getManifest().version, candidates[Number(sources.value)].url, mode, options.cryptoAPI, mode === 'video' ? $('media-quality').value : undefined);
      const reply = await sendMediaRequest(api, request, options.timeoutMs);
      if (reply.jobID) {
        const job = { id: reply.jobID, mode, created: Date.now() };
        try { storage?.setItem(key, JSON.stringify(job)); } catch { /* Live tracking still works. */ }
        await poll(job);
      } else { report('Demande transmise. Consultez Téléchargements web dans EasyPaste pour suivre le résultat.', 'unknown'); controls(false); }
    } catch (error) { report(error.message || 'Impossible de lancer le téléchargement.', 'error'); controls(false); }
  });
  inspect().catch(() => { card.hidden = true; $('nav-download').disabled = true; });
}
