const fs = require('fs');
const path = require('path');
const {spawnSync} = require('child_process');
const root = __dirname;
const test = process.argv.includes('--test');
const check = process.argv.includes('--check');
const sleep = ms => new Promise(r => setTimeout(r, ms));
function log(s) { const line = new Date().toLocaleString()+' '+s; console.log(line); fs.appendFileSync(path.join(root,'reconnect.log'),line+'\n'); }
async function online() {
  try { const r = await fetch('http://www.msftconnecttest.com/connecttest.txt',{signal:AbortSignal.timeout(10000)}); return (await r.text()).trim()==='Microsoft Connect Test'; }
  catch { return false; }
}
function credentials() {
  const script = "[Console]::OutputEncoding=[Text.Encoding]::UTF8; $ErrorActionPreference='Stop'; $c=Import-Clixml -LiteralPath $env:CAMPUS_CREDENTIAL_FILE; @{username=$c.UserName;password=$c.GetNetworkCredential().Password}|ConvertTo-Json -Compress";
  const r = spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',script],{encoding:'utf8',timeout:20000,windowsHide:true,env:{...process.env,CAMPUS_CREDENTIAL_FILE:path.join(root,'credentials.xml')}});
  if(r.status!==0) throw Error('CredentialReadFailed');
  return JSON.parse(r.stdout.replace(/^\uFEFF/,''));
}
async function visible(loc) { for(const e of await loc.all()) if(await e.isVisible() && await e.isEnabled()) return e; return null; }
async function structure(page) {
  const data=[];
  for(const f of page.frames()) { try {data.push({host:new URL(f.url()).hostname,fields:await f.locator('input,button,select,a[onclick]').evaluateAll(es=>es.map(e=>({tag:e.tagName,type:e.getAttribute('type'),id:e.id,name:e.getAttribute('name'),visible:!!(e.offsetWidth||e.offsetHeight||e.getClientRects().length)})))});}catch{} }
  fs.writeFileSync(path.join(root,'portal-structure.json'),JSON.stringify(data,null,2));
}
async function login(browser,c) {
  const ctx=await browser.newContext(); let stage='open portal';
  try {
    const page=await ctx.newPage(); page.setDefaultTimeout(12000);
    const host=()=>{try{return new URL(page.url()).hostname;}catch{return '';}};
    for(const url of ['http://www.msftconnecttest.com/redirect','http://portal.ahau.edu.cn/']) {
      if(host()==='portal.ahau.edu.cn') break;
      log('Opening portal...');
      try {await page.goto(url,{waitUntil:'domcontentloaded',timeout:20000});}
      catch(e){log('Navigation: '+(e.message.match(/net::ERR_[A-Z_]+/)||[e.name])[0]+'; inspecting loaded page.');}
      await page.waitForTimeout(2000);
    }
    stage='find fields'; log('Looking for login form (20 seconds)...'); let target;
    for(let i=0;i<20&&!target;i++) {
      for(const f of page.frames()) {
        try {
          if(new URL(f.url()).hostname!=='portal.ahau.edu.cn') continue;
          const pw=await visible(f.locator('input[type="password"]'));
          let user=await visible(f.locator('input[name*="user" i],input[id*="user" i],input[name*="account" i],input[id*="account" i]'));
          if(!user) user=await visible(f.locator('input[type="text"],input[type="tel"],input:not([type])'));
          if(pw&&user){target={f,pw,user};break;}
        }catch{}
      }
      if(!target) await page.waitForTimeout(1000);
    }
    if(test) {await structure(page); log('Saved portal-structure.json (no field values).');}
    if(!target) throw Error('UnsupportedPortalForm');
    const {f,pw,user}=target; stage='fill credentials';
    log('Login form found; filling credentials...');
    await user.fill(c.username); await pw.fill(c.password);
    let b=await visible(f.getByRole('button',{name:/登.?录|login|sign in/i}));
    if(!b) b=await visible(f.locator('input[type="submit"],button[type="submit"],#login,#loginButton'));
    if(!b) b=await visible(f.getByText(/^\s*(登\s*录|Login|Sign in)\s*$/i));
    stage='submit login'; log('Submitting login...');
    if(b) await b.click(); else await pw.press('Enter');
    await page.waitForTimeout(5000);
  } catch(e) {log('Failed at stage: '+stage+' ('+e.name+').'); throw e;}
  finally { if(test){log('Keeping browser visible for 30 seconds. Hide passwords in screenshots.');await sleep(30000);} await ctx.close(); }
}
async function main() {
  const cfg=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\uFEFF/,''));
  const {chromium}=require(cfg.playwright);
  if(check) {
    const browser=await chromium.launch({channel:'msedge',headless:true,timeout:20000});
    try {const p=await browser.newPage();await p.goto('about:blank');log('CHECK OK: Node, Playwright and Edge started.');}finally{await browser.close();} return;
  }
  log('Starting '+(test?'visible one-attempt test':'scheduled reconnect'));
  if(new Date().getHours()<6){log('School offline period 00:00-06:00.');return;}
  log('Checking Internet (10 seconds)...'); if(await online()){log('Already online; no login needed.');return;}
  const c=credentials(); log('Encrypted credentials read. Starting Edge...');
  const browser=await chromium.launch({channel:'msedge',headless:!test,timeout:20000});
  try {
    const count=test?1:30;
    for(let i=0;i<count;i++) {
      if(new Date().getHours()<6) return;
      log('Login attempt '+(i+1)+'/'+count);
      try {await login(browser,c);if(await online()){log('SUCCESS: Internet verified.');return;}}catch{}
      if(i<count-1){log('Retrying in 60 seconds...');await sleep(60000);}
    }
    log('Login unsuccessful. Send log and portal-structure.json for adaptation.');process.exitCode=1;
  } finally {await browser.close();}
}
main().catch(e=>{if(check) console.error(e.message); log('Stopped: '+e.name+'. Check runtime, security notifications and installation.');process.exitCode=1;});

