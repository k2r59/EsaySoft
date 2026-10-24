import { inspectYouTube, readCaptionTrack, readDisplayedTranscript, readNativeTranscript } from "./src/youtube.js";
import { parseCaptions, formatTranscript } from "./src/captions.js";
import { clipboardPayload, writeRichClipboard } from "./src/clipboard.js";
import { mountNativeCard } from "./src/native.js";

const $ = id => document.getElementById(id);
let tabId, initialURL, info, youtube, busy = false;

function feedback(message, kind = "info") {
  $("feedback").dataset.kind = kind;
  $("feedback-text").textContent = message;
}
function setBusy(value) {
  busy = value;
  for (const button of document.querySelectorAll("#page-card button, #youtube button")) button.disabled = value;
  $("copy-page").disabled = value || !info;
  $("copy-captions").disabled = value || !youtube?.hasAvailable;
  document.body.setAttribute("aria-busy", String(value));
}
async function execute(func, args = [], world = "ISOLATED") {
  const results = await chrome.scripting.executeScript({ target: { tabId }, func, args, world });
  const result = results.find(value => value.frameId === 0)?.result;
  if (result === undefined) throw new Error("La page a changé. Fermez puis rouvrez EasyPaste.");
  return result;
}
async function action(task) {
  if (busy) return;
  setBusy(true); feedback("Préparation de la copie…");
  try { await task(); }
  catch (error) { feedback(error?.message || "La copie a échoué. Réessayez sur une page web classique.", "error"); }
  finally { setBusy(false); }
}
async function copyWithSource({ text, html }) {
  const currentURL = await execute(() => location.href);
  if (currentURL !== initialURL) throw new Error("La page a changé. Fermez puis rouvrez EasyPaste.");
  const payload = clipboardPayload({ text, html, sourceURL: initialURL });
  writeRichClipboard(payload);
}
async function refreshYouTube() {
  youtube = await execute(inspectYouTube, [], "MAIN");
  $("youtube").hidden = !youtube?.videoId;
  if (!youtube?.videoId) return;
  $("page-card").open = false;
  const select = $("track"); select.replaceChildren();
  const tracks = Array.isArray(youtube.tracks) ? youtube.tracks.slice(0, 100) : [];
  const displayed = await execute(readDisplayedTranscript, [youtube.videoId, true]);
  youtube.hasAvailable = tracks.length > 0 || displayed.available === true || displayed.canOpen === true;
  const domOption = new Option("Transcription YouTube", "dom");
  domOption.disabled = !youtube.hasAvailable;
  select.add(domOption);
  tracks.forEach((track, index) => select.add(new Option(`${track.label}${track.automatic ? " · auto" : ""} · piste directe`, String(index))));
  if (!youtube.hasAvailable) { const empty = new Option("Aucune piste disponible", ""); empty.disabled = true; select.add(empty); select.value = ""; }
  select.disabled = !youtube.hasAvailable;
  $("caption-count").textContent = tracks.length ? String(tracks.length) : "";
  $("caption-info").textContent = youtube.hasAvailable
    ? "La transcription s’ouvre automatiquement dans YouTube. Sa langue est celle du panneau."
    : "Aucune piste accessible pour le moment. Si YouTube propose « Afficher la transcription », ouvrez-la puis rouvrez EasyPaste.";
  if (youtube.hasAvailable) select.value = "dom";
  $("copy-captions").disabled = !youtube.hasAvailable;
}

$("copy-page").addEventListener("click", () => action(async () => {
  const result = await execute(async (scope, attribution, expectedURL) => {
    if (location.href !== expectedURL) return { error: "La page a changé. Fermez puis rouvrez EasyPaste." };
    try { return await globalThis.EasyPasteWeb.collect({ scope, attribution }); }
    catch (error) { return { error: error.message }; }
  }, [$("scope").value, $("attribution").checked, initialURL]);
  if (result.error) throw new Error(result.error);
  await copyWithSource(result);
  feedback(result.omittedImages ? "Copié avec la mise en forme. Les images distantes ont été laissées de côté." : "Copié avec la mise en forme. Prêt à coller.", "success");
}));

$("copy-captions").addEventListener("click", () => action(async () => {
  const selected = $("track").value;
  let cues, native = selected === "dom";
  async function nativeCues() {
    feedback("Lecture de la transcription YouTube… Gardez cette fenêtre ouverte.");
    const result = await execute(readNativeTranscript, [youtube.videoId]);
    if (result.error) throw new Error(result.error);
    if (!result.cues?.length) throw new Error("Aucune transcription lisible n’a été trouvée dans YouTube.");
    native = true;
    return result.cues;
  }
  if (native) {
    cues = await nativeCues();
  } else {
    const track = youtube.tracks[Number(selected)];
    if (!track) throw new Error("Choisissez une piste de sous-titres.");
    const result = await execute(readCaptionTrack, [track.url, youtube.videoId]);
    if (result.code === "empty" && youtube.tracks.length === 1) cues = await nativeCues();
    else {
      if (result.error) throw new Error(result.code === "empty" ? "Cette piste directe est vide. Choisissez « Transcription YouTube » pour lire le panneau natif." : result.error);
      cues = parseCaptions(result.body);
    }
  }
  const text = formatTranscript(cues, { timestamps: $("timestamps").checked });
  await copyWithSource({ text });
  feedback(`${native ? "Transcription YouTube copiée" : "Sous-titres copiés"} · ${cues.length} passages.`, "success");
}));
$("refresh").addEventListener("click", () => action(async () => { await refreshYouTube(); feedback("Pistes actualisées."); }));

async function initialize() {
  setBusy(true);
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !/^https?:\/\//.test(tab.url || "")) throw new Error("Ouvrez une page web : les pages internes de Chrome et les fichiers PDF ne sont pas accessibles.");
    tabId = tab.id; initialURL = tab.url;
    $("domain").textContent = new URL(tab.url).hostname;
    await chrome.scripting.executeScript({ target: { tabId }, files: ["src/content.js", "src/transcript.js"] });
    info = await execute(() => globalThis.EasyPasteWeb.pageInfo());
    initialURL = info.url;
    $("page-title").textContent = info.title || "Page sans titre";
    $("scope").disabled = false;
    $("selection-option").disabled = !info.selected;
    $("scope").value = info.selected ? "selection" : "page";
    // Only enter the page's JS world for the supported YouTube hosts, never on other sites.
    if (["www.youtube.com", "m.youtube.com", "youtube.com"].includes(new URL(info.url).hostname)) await refreshYouTube();
  } catch (error) {
    $("page-title").textContent = "Page non accessible";
    feedback(error?.message?.startsWith("Ouvrez") ? error.message : "Chrome ne permet pas de copier cette page. Essayez sur un article ou sélectionnez du texte sur une page web.", "error");
  } finally { setBusy(false); }
}
mountNativeCard();
initialize();
