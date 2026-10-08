import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { createHandler, sanitizeMerchant } from "./handler.mjs";
if (!globalThis.crypto) globalThis.crypto = webcrypto;
const secret = "x".repeat(48);
const env = name => ({ YUEJI_ACCESS_TOKEN: secret, GEMINI_API_KEY: "test-key", GEMINI_MODEL: "gemini-test" })[name];
const request = (body = { merchant: "Kung Fu Soup" }, token = secret) =>
  new Request("https://example.invalid/classify", { method: "POST",
    headers: { "Content-Type": "application/json", "X-YueJi-Token": token }, body: JSON.stringify(body) });
const reply = (value, finishReason = "STOP") => Response.json({
  candidates: [{ finishReason, content: { parts: [{ text: JSON.stringify(value) }] } }],
});
const value = { category: "餐饮", confidence: 0.95, needsReview: false, reason: "汤品餐饮商户" };
test("authenticated merchant-only request uses structured Gemini response", async () => {
  let called = 0;
  const handler = createHandler({ env, fetchImpl: async (url, init) => {
    called++;
    assert.match(url, /gemini-test:generateContent$/);
    assert.equal(init.headers["x-goog-api-key"], "test-key");
    const payload = JSON.parse(init.body);
    assert.deepEqual(JSON.parse(payload.contents[0].parts[0].text), { merchant: "Kung Fu Soup" });
    assert.ok(payload.generationConfig.responseJsonSchema.properties.category.enum.includes("餐饮"));
    return reply(value);
  } });
  const response = await handler(request());
  assert.equal(response.status, 200); assert.deepEqual(await response.json(), value); assert.equal(called, 1);
});
test("unauthorized and missing configuration never call Gemini", async () => {
  const fetchImpl = () => { throw new Error("must not call"); };
  assert.equal((await createHandler({ env, fetchImpl })(request({}, "bad"))).status, 401);
  assert.equal((await createHandler({ env: () => "", fetchImpl })(request())).status, 503);
});
test("reject full notifications and oversized payloads", async () => {
  const handler = createHandler({ env, fetchImpl: () => { throw new Error("must not call"); } });
  assert.equal((await handler(request({ merchant: "Shop", body: "bank private data" }))).status, 400);
  assert.equal((await handler(request({ merchant: "x".repeat(3000) }))).status, 413);
});
test("uncertain and unknown replies require review", async () => {
  for (const result of [{ ...value, confidence: 0.6 }, { ...value, category: "其他" }]) {
    const handler = createHandler({ env, fetchImpl: async () => reply(result) });
    assert.equal((await (await handler(request())).json()).needsReview, true);
  }
});
test("invalid category/confidence and incomplete output fail closed", async () => {
  for (const result of [{ ...value, category: "删除账目" }, { ...value, confidence: 2 }, { ...value, needsReview: "false" }]) {
    assert.equal((await createHandler({ env, fetchImpl: async () => reply(result) })(request())).status, 502);
  }
  assert.equal((await createHandler({ env, fetchImpl: async () => reply(value, "MAX_TOKENS") })(request())).status, 502);
});
test("upstream errors don't expose keys or raw error details", async () => {
  for (const status of [401, 429, 500]) {
    const handler = createHandler({ env, fetchImpl: async () => new Response("PRIVATE KEY", { status }) });
    const response = await handler(request());
    assert.equal(response.status, status === 429 ? 429 : 502);
    assert.ok(!(await response.text()).includes("PRIVATE KEY"));
  }
});
test("redact identifiers but retain ordinary merchant names", () => {
  assert.equal(sanitizeMerchant("Kung Fu Soup"), "Kung Fu Soup");
  assert.equal(sanitizeMerchant("99 Speedmart"), "99 Speedmart");
  const sanitized = sanitizeMerchant("CAFE 1234-5678-9012-3456 test@example.com");
  assert.ok(!sanitized.includes("1234")); assert.ok(!sanitized.includes("@"));
});
test("burst limit prevents further upstream calls", async () => {
  let called = 0;
  const handler = createHandler({ env, now: () => 100_000, fetchImpl: async () => { called++; return reply(value); } });
  for (let i = 0; i < 20; i++) assert.equal((await handler(request())).status, 200);
  assert.equal((await handler(request())).status, 429); assert.equal(called, 20);
});

