import { mountMediaCard } from "./src/media.js";
import { youtubeDirect, readTranscriptModel } from "./src/youtube-archive.js";
import { inspectYouTube, readDisplayedTranscript, readNativeTranscript } from "./src/youtube.js";
import { parseCaptions, formatTranscript, normalizeCues } from "./src/captions.js";
import { clipboardPayload, writeRichClipboard } from "./src/clipboard.js";
import { mountNativeCard } from "./src/native.js";

const $ = id => document.getElementById(id);
let tabId, initialURL, info, youtube, busy = false, previewCues = null;
let screen = "home";

function feedback(message, kind = "info") {
  $("feedback").hidden = !message;
  $("feedback").dataset.kind = kind;
  $("feedback-text").textContent = message;
}
function setBusy(value) {
  busy = value;
  for (const button of document.querySelectorAll("#page-card button, #youtube button")) button.disabled = value;
  $("copy-page").disabled = value || !info;
  $("copy-captions").disabled = value || !youtube?.hasAvailable;
  $("preview-captions").disabled = value || !youtube?.hasAvailable;
  $("nav-page").disabled = value || !info;
  $("nav-captions").disabled = value || !youtube?.videoId;
  $("track").disabled = value || !youtube?.hasAvailable;
  $("timestamps").disabled = value;
  $("transcript-text").disabled = value;
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
  clearPreview();
  youtube = await execute(inspectYouTube, [], "MAIN");
  $("youtube").hidden = !youtube?.videoId;
  if (!youtube?.videoId) return;

  const select = $("track"); select.replaceChildren();
  let discoveryError;
  if (!youtube.tracks?.length) {
    feedback("Recherche des langues sur YouTube…");
    const fresh = await execute(youtubeDirect, ["list", youtube.videoId], "MAIN");
    if (fresh.error) discoveryError = fresh.error;
    else youtube.tracks = fresh.tracks;
  }
  const model = await execute(readTranscriptModel, [youtube.videoId], "MAIN");
  const tracks = Array.isArray(youtube.tracks) ? youtube.tracks.slice(0, 100) : [];
  const displayed = await execute(readDisplayedTranscript, [youtube.videoId, true]);
  youtube.hasAvailable = tracks.length > 0 || displayed.available === true || displayed.canOpen === true || model.cues?.length > 0;
  const domOption = new Option("Transcription YouTube", "dom");
  domOption.disabled = !youtube.hasAvailable;
  select.add(domOption);
  tracks.forEach((track, index) => select.add(new Option(`${track.label}${track.automatic ? " · Automatiques" : ""}`, String(index))));
  if (!youtube.hasAvailable) { const empty = new Option("Aucune piste disponible", ""); empty.disabled = true; select.add(empty); select.value = ""; }
  select.disabled = !youtube.hasAvailable;
  $("caption-count").textContent = tracks.length ? String(tracks.length) : "";
  $("caption-info").textContent = youtube.hasAvailable
    ? ""
    : "Aucune piste accessible pour le moment. Si YouTube propose « Afficher la transcription », ouvrez-la puis rouvrez EasyPaste.";
  if (youtube.hasAvailable) {
    const preferred = tracks.findIndex(t => /^fr(?:-|$)/.test(t.language) && !t.automatic);
    const french = tracks.findIndex(t => /^fr(?:-|$)/.test(t.language));
    select.value = tracks.length ? String(preferred >= 0 ? preferred : french >= 0 ? french : 0) : "dom";
  }
  $("caption-info").hidden = youtube.hasAvailable;
  $("caption-availability").textContent = youtube.hasAvailable ? "Disponible" : "Indisponible";
  $("caption-availability").dataset.state = youtube.hasAvailable ? "available" : "unavailable";
  if (discoveryError && screen === "captions") feedback(discoveryError, "error");
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

function clearPreview() {
  previewCues = null;
  $("transcript-text").value = "";
  $("transcript-preview").hidden = true;
  $("preview-captions").hidden = false;
}
function updatePreview() {
  $("transcript-text").value = formatTranscript(previewCues, { timestamps: $("timestamps").checked });
  $("transcript-preview").hidden = false;
  $("preview-captions").hidden = true;
  updateCount();
}
function updateCount() {
  $("transcript-count").textContent = `${$("transcript-text").value.length.toLocaleString("fr-FR")} caractères`;
  $("copy-captions").disabled = busy || !youtube?.hasAvailable || (previewCues && !$("transcript-text").value.trim());
}
async function retrieveCues() {
  clearPreview();
  const selected = $("track").value;
  let cues;
  if (selected === "dom") {
    feedback("Lecture de la transcription YouTube… Gardez cette fenêtre ouverte.");
    let model = await execute(readTranscriptModel, [youtube.videoId, true], "MAIN");
    if (model.error) throw new Error(model.error);
    if (model.cues?.length) cues = model.cues;
    else {
      const result = await execute(readNativeTranscript, [youtube.videoId]);
      // Opening the native panel can also populate the complete modern model.
      model = await execute(readTranscriptModel, [youtube.videoId], "MAIN");
      if (model.error) throw new Error(model.error);
      if (model.cues?.length) cues = model.cues;
      else {
        if (result.error) throw new Error(result.error);
        cues = result.cues;
      }
    }
  } else {
    const track = youtube.tracks[Number(selected)];
    if (!track) throw new Error("Choisissez une piste de sous-titres.");
    feedback(`Récupération : ${track.label}… Gardez cette fenêtre ouverte.`);
    const result = await execute(youtubeDirect, ["read", youtube.videoId, track], "MAIN");
    if (result.error) throw new Error(result.error);
    cues = parseCaptions(result.body);
  }
  previewCues = normalizeCues(cues);
  updatePreview();
}
$("copy-captions").addEventListener("click", () => action(async () => {
  if (!previewCues) await retrieveCues();
  const text = $("transcript-text").value;
  if (!text.trim() || text.length > 500000) throw new Error("Le texte doit contenir entre 1 et 500 000 caractères.");
  await copyWithSource({ text });
  feedback("Sous-titres copiés. Prêts à coller.", "success");
}));
async function loadPreview() {
  await action(async () => { await retrieveCues(); feedback(""); });
}
$("preview-captions").addEventListener("click", loadPreview);
$("track").addEventListener("change", () => {
  clearPreview();
  if (screen === "captions") loadPreview();
});
$("transcript-text").addEventListener("input", updateCount);
$("timestamps").addEventListener("change", () => {
  if (previewCues) {
    updatePreview();
    feedback("Aperçu régénéré avec le format choisi ; les modifications manuelles ont été réinitialisées.");
  }
});
$("refresh").addEventListener("click", () => action(async () => { await refreshYouTube(); if (youtube?.hasAvailable) await retrieveCues(); feedback(""); }));
async function navigate(next) {
  screen = next;
  for (const section of document.querySelectorAll("main > .screen")) section.hidden = section.id !== (next === "home" ? "home" : `${next}-screen`);
  document.querySelector("main").scrollTop = 0;
  feedback("");
  const heading = document.querySelector(".screen:not([hidden]) h2");
  if (heading) { heading.tabIndex = -1; heading.focus(); }
  if (next === "captions" && youtube?.hasAvailable && !previewCues && !busy) await loadPreview();
}
for (const button of document.querySelectorAll("[data-screen]")) button.addEventListener("click", () => navigate(button.dataset.screen));
document.addEventListener("keydown", event => {
  if (event.key === "Escape" && screen !== "home") { event.preventDefault(); event.stopPropagation(); navigate("home"); }
});

async function initialize() {
  setBusy(true);
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !/^https?:\/\//.test(tab.url || "")) throw new Error("Ouvrez une page web : les pages internes de Chrome et les fichiers PDF ne sont pas accessibles.");
    tabId = tab.id; initialURL = tab.url;
    $("domain").textContent = new URL(tab.url).hostname.replace(/^www\./, "");
    await chrome.scripting.executeScript({ target: { tabId }, files: ["src/content.js", "src/transcript.js"] });
    info = await execute(() => globalThis.EasyPasteWeb.pageInfo());
    initialURL = info.url;
    $("page-title").textContent = info.title || "Page sans titre";
    $("media-title").textContent = info.title || "Média de la page";
    $("scope").disabled = false;
    $("selection-option").disabled = !info.selected;
    $("scope").value = info.selected ? "selection" : "page";
    // Only enter the page's JS world for the supported YouTube hosts, never on other sites.
    if (["www.youtube.com", "m.youtube.com", "youtube.com"].includes(new URL(info.url).hostname)) {
      $("domain").textContent = "YouTube";
      $("site-icon").classList.add("youtube");
      $("site-icon").innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 5 11 7-11 7z"/></svg>';
      try { await refreshYouTube(); }
      catch (error) { feedback(error.message || "YouTube n’est pas accessible pour le moment.", "error"); }
    } else {
      $("caption-availability").textContent = "Sur YouTube";
      $("caption-availability").dataset.state = "unavailable";
    }
    if ($("feedback").dataset.kind !== "error") feedback("");
  } catch (error) {
    $("page-title").textContent = "Page non accessible";
    feedback(error?.message?.startsWith("Ouvrez") ? error.message : "Chrome ne permet pas de copier cette page. Essayez sur un article ou sélectionnez du texte sur une page web.", "error");
  } finally { setBusy(false); }
}
mountNativeCard();
mountMediaCard();
initialize();
