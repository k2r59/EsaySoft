import { test } from 'node:test';
import assert from 'node:assert/strict';
import { page } from './helpers.mjs';
import { youtubeDirect, readTranscriptModel } from '../src/youtube-archive.js';
import { parseCaptions, normalizeCues } from '../src/captions.js';
const id = 'abcdefghijk';
const track = (language = 'fr', kind = '') => ({ languageCode: language, kind, name: { simpleText: language }, baseUrl: `https://www.youtube.com/api/timedtext?v=${id}&lang=${language}${kind ? '&kind=' + kind : ''}` });
const player = tracks => ({ videoDetails: { videoId: id }, captions: { playerCaptionsTracklistRenderer: { captionTracks: tracks } } });
const body = JSON.stringify({ events: [{ tStartMs: 2000, segs: [{ utf8: 'Bonjour\u200B !' }] }, { tStartMs: 5000, segs: [{ utf8: 'Suite' }] }] });
function fixture({ tracks = [track()], caption = body, html = '{"VISITOR_DATA":"anonymous-visitor"}', playerData, url = `https://www.youtube.com/watch?v=${id}` } = {}) {
  const site = page('', url), calls = [];
  site.dom.window.TextDecoder = TextDecoder;
  site.dom.window.fetch = async (url, options) => {
    calls.push({ url, options });
    if (url.includes('/watch?')) return new Response(html);
    if (url.includes('/youtubei/')) return new Response(JSON.stringify(playerData || player(tracks)));
    return new Response(caption);
  };
  const run = (op = 'read', selected = { language: 'fr', automatic: false }) => site.dom.window.eval(`(${youtubeDirect.toString()})(${JSON.stringify(op)},${JSON.stringify(id)},${JSON.stringify(selected)})`);
  return { ...site, calls, run };
}
test('archive retrieval refreshes anonymous visitor and exact language, never sends cookies', async () => {
  const f = fixture(); const result = await f.run();
  assert.deepEqual(parseCaptions(result.body), [{ start: 2, text: 'Bonjour !' }, { start: 5, text: 'Suite' }]);
  assert.equal(f.calls.length, 3);
  for (const c of f.calls) { assert.equal(c.options.credentials, 'omit'); assert.equal(c.options.redirect, 'error'); assert.equal(c.options.cache, 'no-store'); }
  assert.equal(JSON.parse(f.calls[1].options.body).context.client.clientName, 'VISIONOS');
  assert.equal(f.calls[1].options.headers['X-Goog-Visitor-Id'], 'anonymous-visitor');
  assert.equal(new URL(f.calls[2].url).searchParams.get('fmt'), 'json3');
  assert.equal(new URL(f.calls[2].url).searchParams.get('lang'), 'fr');
});
test('manual and automatic tracks in the same language stay distinct', async () => {
  const f = fixture({ tracks: [track('fr'), track('fr', 'asr')] });
  assert.ok((await f.run('list')).tracks.length === 2);
  const result = await f.run('read', { language: 'fr', automatic: true });
  assert.ok(result.body); assert.equal(new URL(f.calls.at(-1).url).searchParams.get('kind'), 'asr');
});
test('missing language, wrong video, translated or untrusted URLs never fetch captions', async () => {
  const badTracks = [
    { ...track(), baseUrl: 'https://evil.test/api/timedtext?v=abcdefghijk&lang=fr' },
    { ...track(), baseUrl: 'https://user@www.youtube.com/api/timedtext?v=abcdefghijk&lang=fr' },
    { ...track(), baseUrl: 'https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=fr&tlang=ja' },
    { ...track(), baseUrl: 'https://www.youtube.com/api/timedtext?v=XXXXXXXXXXX&lang=fr' },
    { ...track(), baseUrl: 'https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=en' },
    { ...track(), baseUrl: 'https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=fr&kind=asr' }, track('en')
  ];
  for (const t of badTracks) { const f = fixture({ tracks: [t] }); assert.ok((await f.run()).error); assert.equal(f.calls.length, 2); }
  const f = fixture({ playerData: { videoDetails: { videoId: 'XXXXXXXXXXX' } } });
  assert.ok((await f.run()).error); assert.equal(f.calls.length, 2);
});
test('empty, malformed, oversized and refused responses yield errors, not success', async () => {
  for (const caption of ['', ' ', 'x'.repeat(2000001)]) assert.ok((await fixture({ caption }).run()).error);
  for (const html of ['', '{"VISITOR_DATA":"bad\\nheader"}', 'x'.repeat(8000001)]) assert.ok((await fixture({ html }).run()).error);
  const f = fixture(); f.dom.window.fetch = async () => new Response('Denied', { status: 403 });
  assert.match((await f.run()).error, /403/);
  assert.throws(() => parseCaptions('not-json'));
});
test('navigation during any request prevents further requests and stale content', async () => {
  for (const stage of [1, 2, 3]) {
    const f = fixture(); const fetch = f.dom.window.fetch;
    f.dom.window.fetch = async (...args) => { const r = await fetch(...args); if (f.calls.length === stage) f.dom.reconfigure({ url: 'https://www.youtube.com/watch?v=XXXXXXXXXXX' }); return r; };
    assert.match((await f.run()).error, /changé/); assert.equal(f.calls.length, stage);
  }
  const f = fixture({ url: 'https://evil.test/watch?v=abcdefghijk' });
  assert.ok((await f.run()).error); assert.equal(f.calls.length, 0);
});
test('Shorts and live URLs resolve the same exact video', async () => {
  for (const path of ['shorts', 'live']) assert.ok((await fixture({ url: `https://www.youtube.com/${path}/${id}` }).run()).body);
});
function modelFixture(rows) {
  const f = page('<ytd-watch-flexy video-id="abcdefghijk"></ytd-watch-flexy><ytd-engagement-panel-section-list-renderer visibility="ENGAGEMENT_PANEL_VISIBILITY_EXPANDED"><input></ytd-engagement-panel-section-list-renderer>', `https://www.youtube.com/watch?v=${id}`);
  const panel = f.document.querySelector('ytd-engagement-panel-section-list-renderer');
  panel.data = { identifier: { tag: 'engagement-panel-timeline-view-consolidated' }, content: rows };
  return { ...f, panel, run: () => f.dom.window.eval(`(${readTranscriptModel.toString()})('${id}')`) };
}
test('new consolidated panel reads the whole model in order, even with no rendered rows', async () => {
  const rows = Array.from({ length: 1000 }, (_, i) => ({ transcriptSegmentViewModel: { timestamp: `${Math.floor(i / 60)}:${String(i % 60).padStart(2, '0')}`, simpleText: `Passage ${i}` } }));
  rows.push(rows[0]); // shared references cannot loop or duplicate
  const f = modelFixture(rows); f.panel.data.content.push(f.panel.data);
  const r = await f.run(); assert.equal(r.cues.length, 1000);
  assert.equal(r.cues[999].text, 'Passage 999'); assert.equal(r.cues[0].start, 0);
});
test('filtered, hidden and stale models cannot become partial or wrong-video copies', async () => {
  const row = { transcriptSegmentViewModel: { timestamp: '0:01', simpleText: 'secret' } };
  const f = modelFixture([row]); f.panel.querySelector('input').value = 'filter';
  assert.match((await f.run()).error, /recherche/);
  f.panel.querySelector('input').value = ''; f.panel.hidden = true;
  assert.equal((await f.run()).cues.length, 0);
  f.panel.hidden = false; f.document.querySelector('ytd-watch-flexy').setAttribute('video-id', 'XXXXXXXXXXX');
  assert.match((await f.run()).error, /changé/);
});
test('oversized model rejects instead of truncating; invalid timestamps are ignored', async () => {
  const f = modelFixture([{ transcriptSegmentViewModel: { timestamp: '0:01', simpleText: 'x'.repeat(500001) } }]);
  assert.match((await f.run()).error, /volumineuse/);
  f.panel.data.content = [{ transcriptSegmentViewModel: { timestamp: 'n/a', simpleText: 'bad' } }];
  assert.equal((await f.run()).cues.length, 0);
});
test('only exact timestamp/text duplicates are removed, including nonadjacent ones', () => {
  assert.deepEqual(normalizeCues([{ start: 1, text: 'Oui' }, { start: 2, text: 'Oui' }, { start: 1, text: 'Oui' }]), [{ start: 1, text: 'Oui' }, { start: 2, text: 'Oui' }]);
});
