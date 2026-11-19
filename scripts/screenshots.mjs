import { chromium } from "playwright-core";

const BASE = process.env.BASE_URL ?? "http://127.0.0.1:18080";
const SETUP_TOKEN = process.env.SETUP_TOKEN ?? "smoke-setup-token";
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? "secret123456";
const OUT = process.env.OUT_DIR ?? "/screens";

async function ensureAdmin() {
  const status = await fetch(`${BASE}/api/v1/auth/setup`).then((response) => response.json());
  if (!status.required) {
    return;
  }
  const response = await fetch(`${BASE}/api/v1/auth/setup`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      username: "admin",
      password: ADMIN_PASSWORD,
      setup_token: SETUP_TOKEN,
    }),
  });
  if (!response.ok && response.status !== 409) {
    throw new Error(`setup failed: ${response.status}`);
  }
}

async function login(page) {
  await page.goto(`${BASE}/login`);
  await page.fill('input[autocomplete="username"]', "admin");
  await page.fill('input[autocomplete="current-password"]', ADMIN_PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForURL(`${BASE}/`, { timeout: 15000 });
}

async function setTheme(page, theme) {
  await page.evaluate((value) => {
    localStorage.setItem("mc-theme", value);
    document.documentElement.classList.toggle("dark", value === "dark");
    document.documentElement.style.colorScheme = value;
  }, theme);
  await page.reload();
  await page.waitForLoadState("networkidle");
}

async function checkA11y(page, label) {
  await page.addScriptTag({ path: "/tmp/node_modules/axe-core/axe.min.js" });
  const violations = await page.evaluate(async () => {
    const result = await axe.run(document, {
      runOnly: { type: "tag", values: ["wcag2a", "wcag2aa"] },
    });
    return result.violations
      .filter((violation) => violation.impact === "critical")
      .map((violation) => `${violation.id}: ${violation.help}`);
  });
  if (violations.length > 0) {
    throw new Error(`${label}: a11y ${violations.join(" | ")}`);
  }
}

async function checkLayout(page, label) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth > window.innerWidth + 2,
  );
  if (overflow) {
    throw new Error(`${label}: horizontal overflow`);
  }
  if ((await page.locator("main").count()) === 0) {
    throw new Error(`${label}: missing main landmark`);
  }
}

const pages = [
  ["home", "/"],
  ["library", "/library"],
  ["tracks", "/library?view=tracks"],
  ["genres", "/library?view=genres"],
  ["profile", "/profile"],
];

await ensureAdmin();

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));

await login(page);
for (const theme of ["light", "dark"]) {
  await setTheme(page, theme);
  for (const [name, path] of pages) {
    await page.goto(`${BASE}${path}`);
    await page.waitForLoadState("networkidle");
    await checkLayout(page, `${theme}-${name}`);
    await checkA11y(page, `${theme}-${name}`);
    await page.screenshot({ path: `${OUT}/${theme}-${name}.png`, fullPage: true });
  }
}

await page.setViewportSize({ width: 390, height: 844 });
await page.goto(`${BASE}/library`);
await page.waitForLoadState("networkidle");
await checkLayout(page, "mobile-library");
await page.screenshot({ path: `${OUT}/mobile-library.png`, fullPage: true });

await browser.close();
if (errors.length > 0) {
  throw new Error(`browser errors: ${errors.join(" | ")}`);
}
console.log("screenshots and layout checks passed");
