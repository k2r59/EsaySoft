// Optional live Chrome test; isolated profile, real extension manifest and real YouTube.
// Writes a short test string to the system clipboard; never reads its previous contents.
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const output = process.env.EASYPASTE_BROWSER_OUTPUT || require('node:os').tmpdir();
const fs=require('fs');
(async()=>{
 fs.mkdirSync(output, { recursive: true });
 const profile=fs.mkdtempSync(require('node:path').join(output, 'easypaste-browser-'));
 const ctx = await chromium.launchPersistentContext(profile,{headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE || chromium.executablePath(),args:['--enable-unsafe-extension-debugging','--window-size=1280,1000'],viewport:{width:1280,height:1000},ignoreDefaultArgs:['--disable-extensions']});
 try {
 const c = await ctx.browser().newBrowserCDPSession();
 const {id}=await c.send('Extensions.loadUnpacked',{path:fileURLToPath(new URL('..', import.meta.url))});
 const page=await ctx.newPage();
 await page.goto('https://www.youtube.com/watch?v=0e3GPea1Tyg',{waitUntil:'domcontentloaded',timeout:45000});
 await page.waitForTimeout(3000);
 console.log('TITLE',await page.title());
 const targets=await c.send('Target.getTargets',{filter:[{type:'tab',exclude:false}]}); const targetInfo=targets.targetInfos.find(t=>t.url.includes('youtube.com/watch'));
 await c.send('Extensions.triggerAction',{id,targetId:targetInfo.targetId});
 await page.waitForTimeout(1000);
 const pt=(await c.send('Target.getTargets')).targetInfos.find(t=>t.url.startsWith('chrome-extension://') && t.type==='page');
 if(!pt) throw Error('No extension popup target');
 const {sessionId}=await c.send('Target.attachToTarget',{targetId:pt.targetId,flatten:false});
 let serial=0;
 async function send(method,params={}) {const mid=++serial;return new Promise((resolve,reject)=>{const handler=event=>{if(event.sessionId!==sessionId)return;const m=JSON.parse(event.message);if(m.id!==mid)return;c.off('Target.receivedMessageFromTarget',handler);m.error?reject(Error(m.error.message)):resolve(m.result);};c.on('Target.receivedMessageFromTarget',handler);c.send('Target.sendMessageToTarget',{sessionId,message:JSON.stringify({id:mid,method,params})}).catch(reject);});}
 async function evaluate(expression){const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true,userGesture:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;}
 async function idle(){for(let i=0;i<150;i++){if(await evaluate('document.body.getAttribute("aria-busy")==="false"'))return;await page.waitForTimeout(400);}throw Error('Popup timeout');}
 await idle();

 async function screenshot(name) {
  // Chromium headless constrains the native popup to498px and repeats compositor tiles
  // beyond that surface. Render its actual DOM/state in a600px page for visual QA.
  const html=await evaluate(`(()=>{const copy=document.documentElement.cloneNode(true);copy.querySelectorAll('script').forEach(n=>n.remove());copy.querySelector('#transcript-text').textContent=document.querySelector('#transcript-text').value;document.querySelectorAll('select').forEach(s=>{copy.querySelectorAll('#'+s.id+' option').forEach(o=>o.toggleAttribute('selected',o.value===s.value));});document.querySelectorAll('input[type=checkbox]').forEach(i=>copy.querySelector('#'+i.id).toggleAttribute('checked',i.checked));return copy.outerHTML;})()`);
  const renderContext=await ctx.browser().newContext({viewport:{width:360,height:600},deviceScaleFactor:2});const preview=await renderContext.newPage();
  await preview.setContent(html.replace('<link rel="stylesheet" href="popup.css">','').replace('src="icons/ribbon.png"',`src="data:image/png;base64,${fs.readFileSync(fileURLToPath(new URL('../icons/ribbon.png',import.meta.url))).toString('base64')}"`));
  await preview.addStyleTag({content:fs.readFileSync(fileURLToPath(new URL('../popup.css',import.meta.url)),'utf8')});
  await preview.waitForTimeout(200); const layout=await preview.evaluate(()=>{const main=document.querySelector('main').getBoundingClientRect();const screen=document.querySelector('.screen:not([hidden])');const cta=screen.querySelector('.bottom-action');return {width:innerWidth,height:innerHeight,horizontalOverflow:document.documentElement.scrollWidth>innerWidth,mainBottom:main.bottom,ctaBottom:cta?.getBoundingClientRect().bottom,headerTop:document.querySelector('header').getBoundingClientRect().top,footerTop:document.querySelector('footer').getBoundingClientRect().top};});console.log('LAYOUT',name,layout);assert.equal(layout.horizontalOverflow,false);if(layout.ctaBottom)assert.ok(layout.ctaBottom<=layout.mainBottom-8,'Primary action must fit above footer'); await preview.screenshot({path:require('node:path').join(output,name)});await renderContext.close();
 }
 await screenshot('extension-home.png');
 await evaluate(`document.querySelector('#nav-captions').click()`); await idle();
 await screenshot('extension-captions.png');
 await evaluate(`document.querySelector('#captions-screen [data-screen="home"]').click();document.querySelector('#nav-download').click()`);
 await page.waitForTimeout(1000); await screenshot('extension-download.png');
 await evaluate(`document.querySelector('#download-screen [data-screen="home"]').click();document.querySelector('#nav-captions').click()`); await idle();
 assert.equal(await evaluate('document.querySelector("#copy-captions").disabled'),false);
 const tracks=await evaluate('[...document.querySelector("#track").options].map(o=>({value:o.value,label:o.textContent}))');
 console.log('TRACKS',tracks);
 for(const language of ['Espagnol','Anglais (générés automatiquement)']){
  const t=tracks.find(t=>t.label.toLowerCase().includes(language.toLowerCase()) && t.value!=='dom');if(!t)continue;
  await evaluate(`document.querySelector('#track').value=${JSON.stringify(t.value)};document.querySelector('#track').dispatchEvent(new Event('change'))`);
  await idle();assert.ok(await evaluate('document.querySelector("#transcript-text").value.length > 10'));console.log('EXTRACTION',t.label,await evaluate(`({feedback:document.querySelector('#feedback-text').textContent,chars:document.querySelector('#transcript-text').value.length,kind:document.querySelector('#feedback').dataset.kind})`));
 }
 // Exercise copy of a manually edited preview through the real extension popup.
 await evaluate(`document.querySelector('#transcript-text').value='Essai EasyPaste — aperçu modifié';document.querySelector('#transcript-text').dispatchEvent(new Event('input'));document.querySelector('#copy-captions').click()`);
 await idle();
 assert.equal(await evaluate('document.querySelector("#feedback").dataset.kind'),'success');
 console.log('COPY',await evaluate(`({kind:document.querySelector('#feedback').dataset.kind,message:document.querySelector('#feedback-text').textContent})`));
 await c.send('Browser.grantPermissions',{permissions:['clipboardReadWrite','clipboardSanitizedWrite'],origin:`chrome-extension://${id}`});
 const clipboard=await evaluate(`(async()=>{const items=await navigator.clipboard.read();const item=items[0];const text=await (await item.getType('text/plain')).text();const html=await (await item.getType('text/html')).text();return {textMatches:text==='Essai EasyPaste — aperçu modifié',hasHTML:item.types.includes('text/html'),sourcePreserved:html.includes('easypaste-source-url')&&html.includes('0e3GPea1Tyg')};})()`);
 assert.deepEqual(clipboard,{textMatches:true,hasHTML:true,sourcePreserved:true});console.log('CLIPBOARD',clipboard);
 await evaluate(`document.querySelector('#track').value='dom';document.querySelector('#track').dispatchEvent(new Event('change'))`);
 await idle();
 assert.ok(await evaluate('document.querySelector("#transcript-text").value.length > 10'));
 console.log('NATIVE',await evaluate(`({kind:document.querySelector('#feedback').dataset.kind,message:document.querySelector('#feedback-text').textContent,characters:document.querySelector('#transcript-text').value.length})`));
 const shot=await send('Page.captureScreenshot',{captureBeyondViewport:true});fs.writeFileSync(require('node:path').join(output, 'youtube-popup.png'),Buffer.from(shot.data,'base64'));

 }finally{await ctx.close();fs.rmSync(profile,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1});
