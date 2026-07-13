import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = path.resolve(import.meta.dirname, "..");
const output = path.resolve(process.env.PROOF_DIR || path.join(root, "proof-results", "local"));
const baseUrl = process.env.BASE_URL || "http://127.0.0.1:4178";
let server;
try {
  if (!process.env.BASE_URL) {
    server = spawn("python3", ["-m", "http.server", "4178", "--bind", "127.0.0.1"], { cwd: root, detached: true, stdio: "ignore" });
    await waitFor(`${baseUrl}/index.html`);
  }
  const playwrightPath = path.resolve(root, "../webot-platform/node_modules/playwright/index.mjs");
  const { chromium } = await import(pathToFileURL(playwrightPath).href);
  const browser = await chromium.launch({ headless: true });
  await mkdir(output, { recursive: true });
  for (const viewport of [{ name: "desktop", width: 1440, height: 1000 }, { name: "mobile", width: 390, height: 844 }]) {
    const page = await browser.newPage({ viewport });
    await page.goto(`${baseUrl}/index.html`, { waitUntil: "networkidle" });
    const cards = page.locator(".agent-card");
    if (await cards.count() !== 5) throw new Error(`${viewport.name}: expected five family cards`);
    await page.getByRole("heading", { name: "Music & Sound", exact: true }).scrollIntoViewIfNeeded();
    await page.locator('[data-agent="Music & Sound"] .agent-select').click();
    if (await page.locator('[data-agent="Music & Sound"]').getAttribute("class").then((value) => !value?.includes("is-selected"))) {
      throw new Error(`${viewport.name}: Music & Sound selection did not persist in the page state`);
    }
    if (await page.locator("body").evaluate((body) => body.scrollWidth > body.clientWidth + 1)) throw new Error(`${viewport.name}: horizontal overflow`);
    await page.screenshot({ path: path.join(output, `${viewport.name}-music-family.png`), fullPage: true });
    await page.close();
  }
  await browser.close();
  console.log(`PASS local human-style browser proof: ${output}`);
} finally {
  if (server?.pid) {
    try { process.kill(-server.pid, "SIGTERM"); } catch {}
  }
}

async function waitFor(url) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    try { if ((await fetch(url)).ok) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${url}`);
}
