// Captures the outside inputs: the full-size Instagram images and a lossless screencast of the enochs.nyc animation.
// See README.md for the ffmpeg commands that turn tmp/ into sources/ and shots/.
import { chromium } from "playwright-core";
import fs from "fs";
fs.mkdirSync("tmp/igfull", { recursive: true });
fs.mkdirSync("tmp/enochs-frames", { recursive: true });
const b = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
// Instagram: largest image source in each embed.
const ip = await b.newPage({ viewport: { width: 540, height: 1000 } });
for (const id of ["DINSnrgNrN5", "DaAcd1CtZZV", "DdK6XYcjeFl"]) {
  await ip.goto(`https://www.instagram.com/p/${id}/embed/`, { waitUntil: "networkidle", timeout: 45000 });
  const srcs = await ip.$$eval("img.EmbeddedMediaImage, .EmbeddedMedia img", (is) => is.map((i) => i.srcset || i.src));
  const best = srcs.flatMap((s) => s.split(",").map((x) => x.trim().split(" "))).sort((a, c) => (parseInt(c[1]) || 0) - (parseInt(a[1]) || 0))[0]?.[0];
  if (!best) { console.log(id, "no image"); continue; }
  const r = await ip.request.get(best);
  fs.writeFileSync(`tmp/igfull/${id}.jpg`, await r.body());
  console.log(id, "saved");
}
// Enoch's: PNG screencast frames with their timestamps, written as an ffmpeg concat list.
const ctx = await b.newContext({ viewport: { width: 1920, height: 1080 } });
const p = await ctx.newPage();
const cdp = await ctx.newCDPSession(p);
const times = [];
let n = 0;
cdp.on("Page.screencastFrame", async (f) => {
  const i = n++;
  fs.writeFileSync(`tmp/enochs-frames/${String(i).padStart(5, "0")}.png`, Buffer.from(f.data, "base64"));
  times.push(f.metadata.timestamp);
  cdp.send("Page.screencastFrameAck", { sessionId: f.sessionId }).catch(() => {});
});
await cdp.send("Page.startScreencast", { format: "png", maxWidth: 1920, maxHeight: 1080, everyNthFrame: 1 });
await p.goto("https://enochs.nyc/", { waitUntil: "load", timeout: 60000 });
await p.waitForTimeout(13000);
await cdp.send("Page.stopScreencast");
const list = times.map((t, i) => `file '${String(i).padStart(5, "0")}.png'\nduration ${((times[i + 1] ?? t + 1 / 30) - t).toFixed(4)}`);
fs.writeFileSync("tmp/enochs-frames/list.txt", list.join("\n") + `\nfile '${String(n - 1).padStart(5, "0")}.png'\n`);
console.log("frames", n, "span", (times.at(-1) - times[0]).toFixed(2));
await b.close();
