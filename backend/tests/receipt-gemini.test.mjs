import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleReceipt, validDraft } from '../../supabase/functions/receipt-gemini/handler.mjs';

const draft = { merchant: 'Cafe', date: '2026-10-30', currency: 'MYR', subtotal: '10.00', tax: '', service: '', discount: '', rounding: '', total: '10.00', items: [{ name: 'Rice', amount: '10.00' }] };
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
function request(body = { image: '/9j/AAAA' }, auth = 'Bearer test-user') {
  return new Request('https://example.test/functions/v1/receipt-gemini', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: auth }, body: JSON.stringify(body) });
}
function harness({ userStatus = 200, quota = true, result = draft, finish = 'STOP', modelStatus = 200 } = {}) {
  const calls = [];
  return { calls, env: name => ({ SUPABASE_URL: 'https://example.test', SUPABASE_ANON_KEY: 'public', GEMINI_API_KEY: 'server-only', GEMINI_RECEIPT_MODEL: 'gemini-test' })[name],
    fetch: async (url, options) => {
      calls.push({ url, options });
      if (url.endsWith('/auth/v1/user')) return json({ id: 'user-1' }, userStatus);
      if (url.endsWith('/claim_receipt_scan')) return json(quota);
      return json({ candidates: [{ finishReason: finish, content: { parts: [{ text: JSON.stringify(result) }] } }] }, modelStatus);
    } };
}
test('requires authentication before any image processing or Gemini request', async () => {
  const deps = harness(); assert.equal((await handleReceipt(request({}, ''), deps)).status, 401); assert.equal(deps.calls.length, 0);
  const invalid = harness({ userStatus: 401 }); assert.equal((await handleReceipt(request(), invalid)).status, 401); assert.equal(invalid.calls.length, 1);
});
test('quota denial never calls Google', async () => {
  const deps = harness({ quota: false }); assert.equal((await handleReceipt(request(), deps)).status, 429); assert.equal(deps.calls.length, 2);
});
test('valid draft is returned without extra model properties', async () => {
  const deps = harness({ result: { ...draft, unwanted: 'private' } });
  const result = await handleReceipt(request(), deps);
  assert.equal(result.status, 200); assert.deepEqual(await result.json(), draft);
  assert.equal(deps.calls[2].options.headers['x-goog-api-key'], 'server-only');
  assert.equal(result.headers.get('Cache-Control'), 'no-store');
});
test('rejects malformed image before spending quota', async () => {
  for (const image of ['garbage', 'https://example.com/image.jpg', '/9j/' + 'A'.repeat(5_333_337)]) {
    const deps = harness(); assert.equal((await handleReceipt(request({ image }), deps)).status, 400); assert.equal(deps.calls.length, 1);
  }
});
test('rejects non MYR, invalid amounts and oversized item lists', async () => {
  for (const result of [{ ...draft, currency: 'USD' }, { ...draft, total: '-10.00' }, { ...draft, total: '10.001' }, { ...draft, items: Array(201).fill(draft.items[0]) }]) {
    assert.equal(validDraft(result), false);
    assert.equal((await handleReceipt(request(), harness({ result }))).status, 422);
  }
});
test('does not accept truncated output or leak upstream errors', async () => {
  assert.equal((await handleReceipt(request(), harness({ finish: 'MAX_TOKENS' }))).status, 422);
  assert.equal((await handleReceipt(request(), harness({ modelStatus: 500 }))).status, 502);
});
