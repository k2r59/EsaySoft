const MAX_BODY = 2000000, MAX_TEXT = 500000, MAX_CUES = 12000;

function cleanText(value) {
  return String(value).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "").replace(/\s+/g, " ").trim();
}

export function normalizeCues(cues) {
  if (!Array.isArray(cues) || cues.length > MAX_CUES) throw new Error("Cette transcription est trop longue.");
  const result = [];
  let length = 0;
  for (const cue of cues) {
    const start = Number(cue?.start);
    if (!Number.isFinite(start) || start < 0 || start > 7 * 24 * 3600 || typeof cue?.text !== "string") continue;
    const text = cleanText(cue.text);
    if (!text) continue;
    length += text.length;
    if (length > MAX_TEXT) throw new Error("Cette transcription est trop longue.");
    // Preserve repeated spoken words; remove only identical duplicate events at the same time.
    if (result.at(-1)?.start === start && result.at(-1)?.text === text) continue;
    result.push({ start, text });
  }
  if (!result.length) throw new Error("YouTube n’a renvoyé aucun sous-titre lisible. Essayez la transcription affichée sur la page.");
  return result;
}

export function parseCaptions(body) {
  if (typeof body !== "string" || body.length > MAX_BODY) throw new Error("La réponse de YouTube est trop volumineuse.");
  const trimmed = body.trim();
  if (!trimmed) throw new Error("YouTube a renvoyé une piste vide. Essayez la transcription affichée sur la page.");
  let cues = [];
  try {
    if (trimmed.startsWith("{")) {
      const data = JSON.parse(trimmed);
      if (!Array.isArray(data.events) || data.events.length > MAX_CUES) throw new Error();
      cues = data.events.filter(event => Number.isFinite(event?.tStartMs) && Array.isArray(event?.segs)).map(event => ({
        start: Number(event.tStartMs) / 1000,
        text: event.segs.map(segment => typeof segment.utf8 === "string" ? segment.utf8 : "").join("")
      }));
    } else {
      if (/<!DOCTYPE|<!ENTITY/i.test(trimmed)) throw new Error();
      const doc = new DOMParser().parseFromString(trimmed, "application/xml");
      if (doc.querySelector("parsererror")) throw new Error();
      const root = doc.documentElement.localName;
      if (root === "transcript") {
        cues = [...doc.querySelectorAll("transcript > text[start]")].map(node => ({ start: Number(node.getAttribute("start")), text: node.textContent }));
      } else if (root === "timedtext") {
        cues = [...doc.querySelectorAll("body > p[t]")].map(node => ({ start: Number(node.getAttribute("t")) / 1000, text: node.textContent }));
      } else throw new Error();
    }
  } catch { throw new Error("Le format renvoyé par YouTube n’est pas lisible. Essayez la transcription affichée sur la page."); }
  return normalizeCues(cues);
}

export function formatTranscript(cues, { timestamps = false } = {}) {
  return normalizeCues(cues).map(cue => {
    if (!timestamps) return cue.text;
    const total = Math.floor(cue.start), hours = Math.floor(total / 3600);
    const stamp = `${hours ? `${hours}:` : ""}${String(Math.floor(total / 60) % 60).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
    return `[${stamp}] ${cue.text}`;
  }).join("\n");
}
