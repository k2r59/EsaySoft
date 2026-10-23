const feedback = document.getElementById("feedback");
document.getElementById("copy").addEventListener("click", async () => {
  try {
    const start = performance.now();
    const result = await EasyPasteWeb.collect({ attribution: false });
    const duration = performance.now() - start;
    await navigator.clipboard.write([new ClipboardItem({ "text/html": new Blob([result.html], { type: "text/html" }), "text/plain": new Blob([result.text], { type: "text/plain" }) })]);
    feedback.textContent = `Copie HTML + texte réussie · extraction ${duration.toFixed(1)} ms.`;
  } catch (error) { feedback.textContent = `Échec : ${error.message}`; }
});
document.getElementById("paste-target").addEventListener("paste", event => {
  const types = [...event.clipboardData.types];
  const html = event.clipboardData.getData("text/html");
  const plain = event.clipboardData.getData("text/plain");
  if (/INVISIBLE_NE_PAS_COPIER|SVG_NE_PAS_COPIER/.test(plain + html)) feedback.textContent = "Échec : contenu exclu présent.";
  else feedback.textContent = `Collage reçu : ${types.join(" + ")} · ${html.includes("<strong") ? "gras présent" : "gras absent"} · ${html.includes("<table") ? "tableau présent" : "tableau absent"} · contenu masqué exclu.`;
});
