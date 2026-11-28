import { chromium } from 'playwright-core';
const B = 'http://127.0.0.1:3031', P = 'figure-drawing-at-enochs', PW = 'promo demo password 2026';
const browser = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
async function session(email) {
  const ctx = await browser.newContext({ viewport: { width: 1000, height: 900 }, deviceScaleFactor: 2, timezoneId: 'America/New_York' });
  const page = await ctx.newPage();
  await page.goto(`${B}/session/new`);
  await page.fill('input[type=email]', email); await page.fill('input[type=password]', PW);
  await page.click('input[type=submit][value="Sign In"]'); await page.waitForLoadState('networkidle');
  if (page.url().includes('/session')) throw new Error(`sign-in failed for ${email}: ${page.url()}`);
  return [ctx, page];
}
async function el(page, name, path, sel, width = 1000) {
  await page.setViewportSize({ width, height: 900 });
  if (path) { await page.goto(B + path); await page.waitForLoadState('networkidle'); }
  const loc = page.locator(sel).first();
  await loc.screenshot({ path: `shots/${name}.png` });
  console.log(name, page.url());
}
const next = async page => { await page.getByRole('link', { name: 'Next Month' }).first().click(); await page.waitForLoadState('networkidle'); await page.waitForTimeout(500); };
let [c, p] = await session('organizer@example.test');
await el(p, 'n-settings', `/programs/${P}/edit`, 'main form');
await el(p, 'n-close', `/programs/${P}/schedule?date=2026-12-28`, 'main form');
await el(p, 'n-notifications', `/programs/${P}/notifications`, 'main table');
await el(p, 'n-google', `/programs/${P}/google_calendar`, 'main', 1000);
await p.setViewportSize({ width: 1280, height: 900 });
await p.goto(`${B}/programs/${P}/calendar`); await p.waitForLoadState('networkidle'); await next(p);
await el(p, 'n-org', null, 'section[data-calendar]', 1280);
await c.close();
[c, p] = await session('model0@example.test');
await el(p, 'n-confirmed', `/profile/bookings`, 'main section, main article, main .card');
await c.close();
[c, p] = await session('model6@example.test');
await p.setViewportSize({ width: 1280, height: 900 });
await p.goto(`${B}/profile/bookings`); await p.getByRole('link', { name: 'Choose a Date' }).click(); await p.waitForLoadState('networkidle');
await next(p); await el(p, 'n-model', null, 'section[data-calendar]', 1280);
await c.close(); await browser.close();
