import { test } from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { page } from './helpers.mjs';
import { detectPageMedia, mediaRequest, sendMediaRequest, mountMediaCard } from '../src/media.js';
const popupHTML = readFileSync(new URL('../popup.html', import.meta.url), 'utf8');
test('detects HTML video/audio beyond YouTube and deduplicates safe URLs', () => {
  const f = page('<video src="/film.mp4"><source src="/film.mp4"><source src="blob:opaque"></video><audio src="https://cdn.example.test/sound.mp3"></audio><meta property="og:video" content="javascript:alert(1)"><meta property="og:audio" content="https://user:password@example.test/private">', 'https://example.test/article');
  const r = f.dom.window.eval(`(${detectPageMedia.toString()})()`);
  assert.equal(r.detected, true); assert.equal(r.candidates.length, 3);
  assert.equal(r.candidates[1].url, 'https://example.test/film.mp4');
  assert.equal(r.candidates[2].url, 'https://cdn.example.test/sound.mp3');
});
test('pages without HTML media tags offer explicit yt-dlp analysis', () => {
  const f = page('<article>Hello</article>');
  const r = f.dom.window.eval(`(${detectPageMedia.toString()})()`);
  assert.equal(r.detected, false); assert.equal(r.candidates.length, 1);
});
test('native media requests reject paths, credentials and arbitrary modes', () => {
  const r = mediaRequest('0.3.0', 'https://vimeo.com/123', 'audio', webcrypto);
  assert.equal(r.type, 'media'); assert.equal(r.mode, 'audio'); assert.match(r.nonce, /^[a-f0-9]{48}$/);
  assert.deepEqual(Object.keys(r).sort(), ['extensionVersion', 'mode', 'nonce', 'protocol', 'type', 'url']);
  for (const url of ['file:///tmp/secret', 'https://user:pass@example.com/a', 'javascript:bad()']) assert.throws(() => mediaRequest('0.3.0', url, 'video', webcrypto));
  assert.throws(() => mediaRequest('0.3.0', 'https://example.com/a', '--exec', webcrypto));
});
test('native replies match the request and mean queued rather than completed', async () => {
  const r = mediaRequest('0.3.0', 'https://example.com/video.mp4', 'video', webcrypto);
  const reply = { protocol: 1, type: 'media', nonce: r.nonce, status: 'queued' };
  const api = response => ({ runtime: { sendNativeMessage: async () => response } });
  assert.equal((await sendMediaRequest(api(reply), r)).status, 'queued');
  for (const patch of [{ nonce: 'wrong' }, { status: 'completed' }, { secret: 'value' }, { message: 'x'.repeat(241) }, { protocol: 2 }]) await assert.rejects(sendMediaRequest(api({ ...reply, ...patch }), r));
  await assert.rejects(sendMediaRequest(api({ ...reply, status: 'disabled' }), r), /Activez/);
  await assert.rejects(sendMediaRequest({ runtime: { sendNativeMessage: () => new Promise(() => {}) } }, r, 5), /ne répond pas/);
});
async function fixture({ granted = true, currentURL = 'https://example.test/article' } = {}) {
  const f = page(popupHTML), sent = [], permissions = [];
  const api = {
    tabs: { query: async () => [{ id: 4, url: 'https://example.test/article' }] },
    scripting: { executeScript: async ({ func }) => [{ frameId: 0, result: func === detectPageMedia ? { pageURL: 'https://example.test/article', detected: true, candidates: [{ url: 'https://example.test/article', label: 'Page' }, { url: 'https://cdn.example.test/video.mp4', label: 'Vidéo' }] } : currentURL }] },
    permissions: { request: async p => { permissions.push(p); return granted; } },
    runtime: { getManifest: () => ({ version: '0.3.0' }), sendNativeMessage: async (host, request) => { sent.push({ host, request }); return { protocol: 1, type: 'media', nonce: request.nonce, status: 'queued' }; } }
  };
  mountMediaCard(f.document, api, { cryptoAPI: webcrypto });
  for (let i = 0; i < 20 && f.document.getElementById('media-card').hidden; i++) await new Promise(r => setTimeout(r, 5));
  return { ...f, sent, permissions };
}
async function settle(f) { for (let i = 0; i < 30 && f.document.getElementById('download-video').disabled; i++) await new Promise(r => setTimeout(r, 5)); }
test('menu uses the selected source and only requests native access on click', async () => {
  const f = await fixture(); assert.equal(f.permissions.length, 0); assert.equal(f.sent.length, 0);
  f.document.getElementById('media-source').value = '1';
  f.document.getElementById('download-audio').click();
  assert.equal(f.sent.length, 0, 'Choosing a format must not start a download');
  f.document.getElementById('download-start').click(); await settle(f);
  assert.equal(f.sent.length, 1); assert.equal(f.sent[0].request.mode, 'audio'); assert.equal(f.sent[0].request.url, 'https://cdn.example.test/video.mp4');
  assert.equal(f.document.getElementById('download-progress').dataset.state, 'unknown', 'Queued alone is not completed');
});
test('denied permission and changed page never start media downloads', async () => {
  for (const config of [{ granted: false }, { currentURL: 'https://example.test/other' }]) {
    const f = await fixture(config); f.document.getElementById('download-start').click(); await settle(f);
    assert.equal(f.sent.length, 0); assert.equal(f.document.getElementById('media-status').dataset.kind, 'error');
    assert.equal(f.document.getElementById('download-video').disabled, false);
  }
});

test('status protocol rejects stale, mismatched and invented completion replies', async () => {
  const { mediaStatus } = await import('../src/media.js');
  const jobID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const api = patch => ({ runtime: { getManifest: () => ({ version: '0.3.0' }), sendNativeMessage: async (_, r) => ({ protocol: 1, type: 'mediaStatus', nonce: r.nonce, jobID, status: 'completed', message: 'Fichier prêt', ...patch }) } });
  assert.equal((await mediaStatus(api({}), jobID, { cryptoAPI: webcrypto })).status, 'completed');
  for (const patch of [{ nonce: 'wrong' }, { jobID: 'other' }, { status: 'done' }, { file: '/private/file' }, { message: 'x'.repeat(241) }]) await assert.rejects(mediaStatus(api(patch), jobID, { cryptoAPI: webcrypto }));
  await assert.rejects(mediaStatus(api({}), '../../file', { cryptoAPI: webcrypto }));
});
test('real queued/preparing/completed replies drive progress and persist only a job identifier', async () => {
  const f = page(popupHTML), saved = new Map(), jobID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  let step = 0;
  const api = {
    tabs: { query: async () => [{ id: 4, url: 'https://example.test/video' }] },
    scripting: { executeScript: async ({ func }) => [{ frameId: 0, result: func === detectPageMedia ? { pageURL: 'https://example.test/video', candidates: [{ url: 'https://example.test/video', label: 'Page' }] } : 'https://example.test/video' }] },
    permissions: { request: async () => true },
    runtime: { getManifest: () => ({ version: '0.3.0' }), sendNativeMessage: async (_, r) => r.type === 'media' ? { protocol: 1, type: 'media', nonce: r.nonce, status: 'queued', jobID } : { protocol: 1, type: 'mediaStatus', nonce: r.nonce, jobID, status: step++ ? 'completed' : 'downloading', message: 'État du moteur' } }
  };
  mountMediaCard(f.document, api, { cryptoAPI: webcrypto, pollMs: 40, storage: { getItem: k => saved.get(k), setItem: (k,v) => saved.set(k,v) } });
  await new Promise(r => setTimeout(r, 5)); f.document.getElementById('download-start').click();
  await new Promise(r => setTimeout(r, 10));
  assert.equal(f.document.getElementById('download-progress').dataset.state, 'downloading');
  assert.equal(f.document.getElementById('download-start').disabled, true);
  await new Promise(r => setTimeout(r, 65));
  assert.equal(f.document.getElementById('download-progress').dataset.state, 'completed');
  assert.equal(f.document.getElementById('download-start').disabled, false);
  assert.deepEqual(Object.keys(JSON.parse(saved.values().next().value)).sort(), ['created', 'id', 'mode']);
  f.dom.window.close();
});
