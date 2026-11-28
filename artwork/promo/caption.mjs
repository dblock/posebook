// Renders tmp/caption.png, the transparent @artdblockdotorg caption laid over the opening.
import { chromium } from "playwright-core";
import fs from "fs";
fs.mkdirSync("tmp", { recursive: true });
const b = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
await p.setContent(`<style>html,body{margin:0;background:transparent}
div{position:absolute;left:72px;bottom:72px;padding:16px 28px;border-radius:14px;background:rgba(30,14,8,.62);
color:#fdf6ec;font:500 38px -apple-system,system-ui,sans-serif;letter-spacing:.3px}
b{font-weight:600;color:#f3c7a8}</style><div><b>@artdblockdotorg</b> · figure drawing at Enoch's</div>`);
await p.screenshot({ path: "tmp/caption.png", omitBackground: true });
await b.close();
