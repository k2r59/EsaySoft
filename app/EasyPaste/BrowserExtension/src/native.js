/* MIT — EasyPaste. One explicit handshake, no persistent port or clipboard access. */
export const NATIVE_HOST = "app.easypaste.web";
const OPTIONAL_ACCESS = { permissions: ["nativeMessaging"] };
const VERSION = /^\d{1,6}(?:\.\d{1,6}){1,3}(?:[-+][A-Za-z0-9.-]{1,32})?$/;

export function helloRequest(version, cryptoAPI = crypto) {
  if (typeof version !== "string" || !VERSION.test(version)) throw new Error("Rechargez l’extension EasyPaste : sa version n’est pas reconnue.");
  const bytes = new Uint8Array(24);
  cryptoAPI.getRandomValues(bytes);
  return { protocol: 1, type: "hello", nonce: [...bytes].map(value => value.toString(16).padStart(2, "0")).join(""), extensionVersion: version };
}

export function validateHello(response, nonce) {
  const fields = ["protocol", "type", "nonce", "bridgeVersion", "appVersion", "status", "message"];
  if (!response || typeof response !== "object" || Array.isArray(response) || Object.keys(response).some(key => !fields.includes(key)) ||
      response.protocol !== 1 || response.type !== "hello" || response.nonce !== nonce || response.bridgeVersion !== 1 ||
      typeof response.appVersion !== "string" || !VERSION.test(response.appVersion) ||
      !["ready", "disabled", "error"].includes(response.status) ||
      (response.message !== undefined && (typeof response.message !== "string" || response.message.length > 240 || /[\u0000-\u001f\u007f]/.test(response.message)))) {
    throw new Error("La réponse d’EasyPaste n’est pas compatible. Mettez à jour l’app et l’extension, puis réessayez.");
  }
  if (response.status === "disabled") throw new Error("La connexion est désactivée dans EasyPaste. Activez-la dans Réglages → Intégrations → Extension navigateur.");
  if (response.status === "error") throw new Error(response.message || "EasyPaste ne peut pas vérifier la connexion. Ouvrez Réglages → Intégrations → Extension navigateur.");
  return { appVersion: response.appVersion, bridgeVersion: response.bridgeVersion };
}

export function nativeFailure(error) {
  const message = String(error?.message || "");
  if (/host.*not found|not.*registered|specified native messaging host not found|failed to start|no such native application/i.test(message)) return "Préparez la connexion dans EasyPaste → Réglages → Intégrations → Extension navigateur, puis réessayez.";
  if (/forbidden|not allowed|access.*denied|nativeMessaging.*permission/i.test(message)) return "Ce navigateur ou cette extension n’est pas autorisé. Préparez à nouveau la connexion dans les réglages d’EasyPaste.";
  if (/exited|disconnected|communicat/i.test(message)) return "EasyPaste a interrompu la vérification. Ouvrez l’app et préparez à nouveau sa connexion navigateur.";
  return "Impossible de joindre EasyPaste. Ouvrez l’app, puis vérifiez Réglages → Intégrations → Extension navigateur.";
}

export async function verifyNative(api, { timeoutMs = 5000, cryptoAPI = crypto } = {}) {
  const request = helloRequest(api.runtime.getManifest().version, cryptoAPI);
  let timer;
  try {
    const response = await Promise.race([
      Promise.resolve().then(() => api.runtime.sendNativeMessage(NATIVE_HOST, request)).catch(error => { throw new Error(nativeFailure(error)); }),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("EasyPaste ne répond pas. Ouvrez l’app et vérifiez sa connexion navigateur, puis réessayez.")), timeoutMs); })
    ]);
    return validateHello(response, request.nonce);
  } finally { clearTimeout(timer); }
}

export function mountNativeCard(doc = document, api = chrome, options = {}) {
  const card = doc.getElementById("mac-card"), connect = doc.getElementById("connect-mac"), disconnect = doc.getElementById("disconnect-mac");
  const status = doc.getElementById("mac-status"), last = doc.getElementById("mac-last-check");
  let granted = false, checking = false;
  function render() {
    card.setAttribute("aria-busy", String(checking));
    connect.disabled = checking; disconnect.disabled = checking;
    connect.textContent = checking ? "Vérification…" : granted ? "Vérifier" : "Connecter";
    disconnect.hidden = !granted;
  }
  function report(text, kind = "info") { status.textContent = text; status.dataset.kind = kind; }
  // Chromium can hide sendNativeMessage until optional nativeMessaging is granted.
  if (typeof api.permissions?.request !== "function") {
    connect.disabled = true; disconnect.hidden = true;
    report("La connexion locale nécessite une version récente de Chrome ou Arc. La copie reste disponible.");
    return;
  }
  connect.addEventListener("click", async () => {
    if (checking) return;
    // Keep the permission request inside the direct user gesture, before any await.
    let permission;
    try { permission = api.permissions.request(OPTIONAL_ACCESS); }
    catch { report("L’accès local a été refusé par le navigateur. La copie reste disponible.", "error"); return; }
    checking = true; render(); report("Vérification locale d’EasyPaste…");
    try {
      try { granted = await permission; }
      catch { throw new Error("L’accès local a été refusé par le navigateur. La copie reste disponible."); }
      if (!granted) { report("Connexion non autorisée. Vous pouvez continuer à copier sans connexion."); return; }
      if (typeof api.runtime?.sendNativeMessage !== "function") {
        throw new Error("L’accès local est autorisé, mais le navigateur ne l’a pas activé. Rechargez l’extension puis réessayez. La copie reste disponible.");
      }
      const response = await verifyNative(api, options);
      const time = new Date().toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
      last.textContent = `Dernière vérification : ${time} · EasyPaste ${response.appVersion}`;
      last.hidden = false;
      report("Connexion locale vérifiée.", "success");
    } catch (error) { report(error.message, "error"); }
    finally { checking = false; render(); }
  });
  disconnect.addEventListener("click", async () => {
    if (checking) return;
    checking = true; render();
    try {
      const removed = await api.permissions.remove(OPTIONAL_ACCESS);
      if (!removed) throw new Error("La déconnexion n’a pas abouti. Réessayez depuis les autorisations de l’extension.");
      granted = false; last.hidden = true; last.textContent = "";
      report("Connexion locale retirée. Vos copies restent disponibles.");
    } catch (error) { report(error.message, "error"); }
    finally { checking = false; render(); }
  });
  checking = true; render();
  Promise.resolve().then(() => api.permissions.contains(OPTIONAL_ACCESS)).then(value => {
    granted = value === true;
    report(granted ? "Accès local autorisé. Vérifiez quand vous en avez besoin." : "Vérifiez le lien avec l’app. La copie fonctionne aussi sans connexion.");
  }).catch(() => report("Vérifiez le lien avec l’app. La copie fonctionne aussi sans connexion.")).finally(() => { checking = false; render(); });
}
