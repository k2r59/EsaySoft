import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHash, webcrypto } from "node:crypto";
import { page } from "./helpers.mjs";
import { helloRequest, validateHello, verifyNative, nativeFailure, mountNativeCard, NATIVE_HOST } from "../src/native.js";

const popupHTML = readFileSync(new URL("../popup.html", import.meta.url), "utf8");
const manifest = JSON.parse(readFileSync(new URL("../manifest.json", import.meta.url), "utf8"));
const ready = request => ({ protocol: 1, type: "hello", nonce: request.nonce, appVersion: "0.3.6", bridgeVersion: 1, status: "ready" });
function apiFixture({ granted = false, request = true, response, error } = {}) {
  const calls = [];
  const api = {
    permissions: {
      contains: async access => { calls.push(["contains", access]); return granted; },
      request: async access => { calls.push(["request", access]); return request; },
      remove: async access => { calls.push(["remove", access]); return true; }
    },
    runtime: {
      getManifest: () => manifest,
      sendNativeMessage: async (host, message) => { calls.push(["send", host, message]); if (error) throw new Error(error); return response ? response(message) : ready(message); }
    }
  };
  return { api, calls };
}
async function settle(doc) {
  for (let i = 0; i < 200 && doc.getElementById("mac-card").getAttribute("aria-busy") !== "false"; i++) await new Promise(resolve => setTimeout(resolve, 2));
  assert.equal(doc.getElementById("mac-card").getAttribute("aria-busy"), "false");
}

test("extension identity is stable and native access stays optional", () => {
  const hash = createHash("sha256").update(Buffer.from(manifest.key, "base64")).digest("hex").slice(0, 32);
  assert.equal(hash.replace(/[0-9a-f]/g, c => String.fromCharCode(97 + parseInt(c, 16))), "nmkechbpakkenabambdbpnaahhdlgpej");
  assert.equal(manifest.version, "0.2.0");
  assert.deepEqual(manifest.optional_permissions, ["nativeMessaging"]);
  assert.deepEqual(manifest.permissions, ["activeTab", "scripting", "clipboardWrite"]);
  assert.equal(manifest.background, undefined); assert.equal(manifest.externally_connectable, undefined);
});
test("hello has bounded random nonces and only handshake fields", () => {
  const first = helloRequest("0.2.0", webcrypto), second = helloRequest("0.2.0", webcrypto);
  assert.deepEqual(Object.keys(first), ["protocol", "type", "nonce", "extensionVersion"]);
  assert.equal(first.protocol, 1); assert.equal(first.type, "hello");
  assert.match(first.nonce, /^[a-f0-9]{48}$/); assert.notEqual(first.nonce, second.nonce);
  assert.throws(() => helloRequest("<script>bad</script>", webcrypto), /version/);
});
test("handshake requires the matching protocol, nonce, type, version and bounded fields", () => {
  const request = helloRequest("0.2.0", webcrypto), response = ready(request);
  assert.equal(validateHello(response, request.nonce).appVersion, "0.3.6");
  for (const patch of [{ protocol: 2 }, { nonce: "wrong" }, { type: "import" }, { status: "connected" }, { bridgeVersion: 2 }, { appVersion: "x".repeat(200) }, { message: "x".repeat(241) }, { message: "line\nbreak" }, { history: ["forbidden"] }]) {
    assert.throws(() => validateHello({ ...response, ...patch }, request.nonce), /compatible/);
  }
  for (const invalid of [null, false, [], "ready"]) assert.throws(() => validateHello(invalid, request.nonce), /compatible/);
  assert.throws(() => validateHello({ ...response, status: "disabled" }, request.nonce), /désactivée/);
  assert.throws(() => validateHello({ ...response, status: "error", message: "Réessayez depuis les réglages." }, request.nonce), /Réessayez/);
});
test("one-shot native verification uses the named host and actionable errors", async () => {
  const { api, calls } = apiFixture();
  assert.equal((await verifyNative(api, { cryptoAPI: webcrypto })).appVersion, "0.3.6");
  assert.equal(calls.length, 1); assert.equal(calls[0][0], "send"); assert.equal(calls[0][1], NATIVE_HOST);
  assert.match(nativeFailure(new Error("Specified native messaging host not found.")), /Préparez/);
  assert.match(nativeFailure(new Error("Access to the specified native messaging host is forbidden.")), /pas autorisé/);
  assert.match(nativeFailure(new Error("Native host has exited.")), /interrompu/);
  assert.doesNotMatch(nativeFailure(new Error("unknown failure secret value")), /secret/);
});
test("native verification times out without a persistent port and ignores a late response", async () => {
  const { api, calls } = apiFixture({ response: request => new Promise(resolve => setTimeout(() => resolve(ready(request)), 40)) });
  await assert.rejects(verifyNative(api, { timeoutMs: 10, cryptoAPI: webcrypto }), /ne répond pas/);
  assert.equal(calls.length, 1);
});
test("popup requests permission synchronously at click and never connects automatically", async () => {
  const { document } = page(popupHTML), { api, calls } = apiFixture();
  mountNativeCard(document, api, { cryptoAPI: webcrypto }); await settle(document);
  assert.equal(calls.filter(call => call[0] === "send").length, 0);
  const before = calls.length;
  document.getElementById("connect-mac").click();
  assert.equal(calls[before][0], "request", "Permission is requested inside the direct click before any await");
  assert.equal(calls.filter(call => call[0] === "send").length, 0);
  await settle(document);
  assert.equal(document.getElementById("mac-status").dataset.kind, "success");
  assert.match(document.getElementById("mac-last-check").textContent, /Dernière vérification.*0.3.6/);
  assert.equal(document.getElementById("connect-mac").textContent, "Vérifier");
  document.getElementById("disconnect-mac").click(); await settle(document);
  assert.deepEqual(calls.at(-1), ["remove", { permissions: ["nativeMessaging"] }]);
  assert.equal(document.getElementById("mac-last-check").hidden, true);
  assert.equal(document.getElementById("connect-mac").textContent, "Connecter");
});
test("popup connects when the browser exposes native messaging only after permission is granted", async () => {
  const { document } = page(popupHTML), { api, calls } = apiFixture();
  const sendNativeMessage = api.runtime.sendNativeMessage;
  delete api.runtime.sendNativeMessage;
  api.permissions.request = async access => {
    calls.push(["request", access]);
    await Promise.resolve();
    api.runtime.sendNativeMessage = sendNativeMessage;
    return true;
  };
  document.getElementById("copy-page").disabled = false;
  mountNativeCard(document, api, { cryptoAPI: webcrypto }); await settle(document);
  assert.equal(document.getElementById("connect-mac").disabled, false);
  assert.equal(api.runtime.sendNativeMessage, undefined);
  const before = calls.length;
  document.getElementById("connect-mac").click();
  assert.equal(calls[before][0], "request");
  assert.equal(api.runtime.sendNativeMessage, undefined, "The API remains hidden until permission resolves");
  await settle(document);
  assert.equal(calls.filter(call => call[0] === "send").length, 1);
  assert.equal(document.getElementById("mac-status").dataset.kind, "success");
  assert.equal(document.getElementById("copy-page").disabled, false);
});
test("missing native messaging after permission gives a recoverable error without blocking copies", async () => {
  const { document } = page(popupHTML), { api, calls } = apiFixture();
  delete api.runtime.sendNativeMessage;
  document.getElementById("copy-page").disabled = false;
  mountNativeCard(document, api, { cryptoAPI: webcrypto }); await settle(document);
  document.getElementById("connect-mac").click(); await settle(document);
  assert.equal(calls.filter(call => call[0] === "request").length, 1);
  assert.equal(calls.filter(call => call[0] === "send").length, 0);
  assert.equal(document.getElementById("mac-status").dataset.kind, "error");
  assert.match(document.getElementById("mac-status").textContent, /Rechargez l’extension/);
  assert.equal(document.getElementById("connect-mac").disabled, false);
  assert.equal(document.getElementById("disconnect-mac").hidden, false);
  assert.equal(document.getElementById("copy-page").disabled, false);
});
test("denied native access and host failure never disable the independent copy controls", async () => {
  for (const configuration of [{ request: false }, { error: "Specified native messaging host not found." }]) {
    const { document } = page(popupHTML), { api, calls } = apiFixture(configuration);
    document.getElementById("copy-page").disabled = false;
    mountNativeCard(document, api, { cryptoAPI: webcrypto }); await settle(document);
    document.getElementById("connect-mac").click(); await settle(document);
    assert.equal(document.getElementById("copy-page").disabled, false);
    assert.notEqual(document.getElementById("mac-status").dataset.kind, "success");
    if (configuration.request === false) assert.equal(calls.filter(call => call[0] === "send").length, 0);
  }
});
test("native error strings remain text and cannot inject markup into the popup", async () => {
  const { document } = page(popupHTML), { api } = apiFixture({ response: request => ({ ...ready(request), status: "error", message: '<img src=x onerror="evil()">' }) });
  mountNativeCard(document, api, { cryptoAPI: webcrypto }); await settle(document);
  document.getElementById("connect-mac").click(); await settle(document);
  assert.equal(document.getElementById("mac-status").querySelector("img"), null);
  assert.match(document.getElementById("mac-status").textContent, /<img/);
});
