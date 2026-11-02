// PostPaid UI end-to-end test (Playwright + Chromium), run against a local Arc-mode fork of Arc Testnet.
//
// How it works: the production build is served by `vite preview`; every browser request to
// rpc.testnet.arc.io is routed to the local fork, and a minimal injected wallet (window.ethereum)
// forwards eth_sendTransaction to the fork, which auto-impersonates the sender. No keys, no real funds.
//
// Run:
//   arc-anvil --fork-url https://rpc.testnet.arc.io --auto-impersonate --port 8545 --silent &
//   npx vite build && npx vite preview --port 4173 --strictPort &
//   node scripts/e2e-fork.cjs
//
// Flow: brand creates a deal via the form (approve + createDeal) → creator accepts and submits proof
// (mobile viewport) → brand clicks "Approve & pay" (deal closes) → creator withdraws from the dashboard.
// Screenshots go to docs/screenshots/e2e-*.png.
const { chromium } = require('playwright');
const APP = 'http://localhost:4173', FORK = 'http://127.0.0.1:8545';
const BRAND = '0xceb064097AEc90d68302DE251C8f6dea662d4E22', CREATOR = '0xa242E7dEA27Ff02Bc39142f0115f369527cABde3';
const shots = require('path').join(__dirname, '..', 'docs', 'screenshots');
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

async function rpc(method, params = []) {
  const r = await fetch(FORK, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) });
  return (await r.json()).result;
}

async function asWallet(browser, addr, mobile = false) {
  const ctx = await browser.newContext({ viewport: mobile ? { width: 375, height: 812 } : { width: 1280, height: 900 } });
  await ctx.route(/https:\/\/rpc\.testnet\.arc\.io.*/, async (route) => {
    const res = await fetch(FORK, { method: 'POST', headers: { 'content-type': 'application/json' }, body: route.request().postData() });
    await route.fulfill({ status: 200, contentType: 'application/json', body: await res.text() });
  });
  await ctx.addInitScript((a) => {
    localStorage.setItem('wagmi.recentConnectorId', '"injected"');
    localStorage.setItem('wagmi.injected.connected', 'true');
    const listeners = {};
    window.ethereum = {
      isMetaMask: true,
      on: (e, f) => { (listeners[e] ||= []).push(f) }, removeListener: () => {},
      request: async ({ method, params }) => {
        if (method === 'eth_requestAccounts' || method === 'eth_accounts') return [a];
        if (method === 'eth_chainId') return '0x4cef52';
        if (method === 'net_version') return '5042002';
        if (method === 'wallet_switchEthereumChain' || method === 'wallet_addEthereumChain') return null;
        if (method === 'wallet_requestPermissions' || method === 'wallet_getPermissions') return [{ parentCapability: 'eth_accounts' }];
        const r = await fetch('https://rpc.testnet.arc.io', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: Date.now(), method, params }) });
        const j = await r.json();
        if (j.error) { const e = new Error(j.error.message); e.code = j.error.code; e.data = j.error.data; throw e; }
        return j.result;
      },
    };
  }, addr);
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 240)); });
  page.on('pageerror', (e) => errors.push('PAGEERROR ' + String(e).slice(0, 240)));
  return { ctx, page, errors };
}

async function waitText(page, re, timeout = 60000) {
  await page.waitForFunction((src) => new RegExp(src).test(document.body.innerText), re.source, { timeout });
}

(async () => {
  const browser = await chromium.launch();
  const result = { steps: [], errors: {} };
  try {
    const next = parseInt(await rpc('eth_call', [{ to: '0x4e51c6f82fb8dadd51d650607f05cbb937d3cfe5', data: '0x4d9879e3' }, 'latest']) || '0x0', 16);
    // 1. Brand creates a deal through the form.
    let { ctx, page, errors } = await asWallet(browser, BRAND);
    await page.goto(APP + '/new', { waitUntil: 'networkidle' });
    await waitText(page, /0xceb0/i).catch(() => {});
    await page.getByPlaceholder('0x...', { exact: true }).fill(CREATOR);
    await page.getByPlaceholder('Spring launch campaign').fill('E2E fork test campaign');
    await page.getByPlaceholder('Launch thread').first().fill('Launch thread');
    await page.getByPlaceholder('0.00').first().fill('0.30');
    await page.locator('select').first().selectOption({ index: 0 });
    await page.screenshot({ path: `${shots}/e2e-1-new-filled.png`, fullPage: true });
    await page.getByRole('button', { name: /Lock USDC & create deal/ }).click();
    await page.waitForURL(/\/deal\/\d+/, { timeout: 90000 });
    const dealId = page.url().match(/\/deal\/(\d+)/)[1];
    await waitText(page, /E2E fork test campaign/);
    await page.screenshot({ path: `${shots}/e2e-2-deal-created.png`, fullPage: true });
    result.steps.push(`brand created deal #${dealId} via form (approve + createDeal)`);
    result.errors.brand1 = errors; await ctx.close();

    // 2. Creator accepts and submits proof (mobile viewport).
    ({ ctx, page, errors } = await asWallet(browser, CREATOR, true));
    await page.goto(`${APP}/deal/${dealId}`, { waitUntil: 'networkidle' });
    await page.getByRole('button', { name: /Accept deal/ }).first().click();
    await waitText(page, /Active/);
    result.steps.push('creator accepted');
    await page.getByRole('button', { name: /^Submit proof$/ }).first().click();
    await page.getByPlaceholder('https://x.com/you/status/...').fill('https://x.com/gregwrites_yy/status/1');
    await page.screenshot({ path: `${shots}/e2e-3-submit-modal-mobile.png`, fullPage: false });
    await page.getByRole('dialog').getByRole('button', { name: /Submit/ }).last().click();
    await waitText(page, /Submitted/);
    await page.screenshot({ path: `${shots}/e2e-4-submitted-mobile.png`, fullPage: true });
    result.steps.push('creator submitted proof');
    result.errors.creator1 = errors; await ctx.close();

    // 3. Brand approves & pays.
    ({ ctx, page, errors } = await asWallet(browser, BRAND));
    await page.goto(`${APP}/deal/${dealId}`, { waitUntil: 'networkidle' });
    await page.getByRole('button', { name: /Approve & pay/ }).first().click();
    await waitText(page, /Released/);
    await waitText(page, /Closed/);
    await page.screenshot({ path: `${shots}/e2e-5-approved.png`, fullPage: true });
    result.steps.push('brand approved → Released, deal Closed');
    result.errors.brand2 = errors; await ctx.close();

    // 4. Creator withdraws from the dashboard.
    ({ ctx, page, errors } = await asWallet(browser, CREATOR));
    await page.goto(`${APP}/dashboard`, { waitUntil: 'networkidle' });
    await waitText(page, /0\.297/);
    await page.screenshot({ path: `${shots}/e2e-6-dashboard-before.png`, fullPage: true });
    await page.getByRole('button', { name: /^Withdraw/ }).first().click();
    await waitText(page, /Nothing to withdraw|0\.00 USDC|\b0\.00\b/);
    await page.screenshot({ path: `${shots}/e2e-7-dashboard-after.png`, fullPage: true });
    result.steps.push('creator withdrew from dashboard');
    result.errors.creator2 = errors; await ctx.close();
    result.dealId = dealId; result.expectedDealId = next;
  } catch (e) {
    result.failure = String(e).slice(0, 600);
  }
  console.log(JSON.stringify(result, null, 1));
  await browser.close();
})();
