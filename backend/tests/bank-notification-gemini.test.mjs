import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleBankNotification } from '../../supabase/functions/bank-notification-gemini/handler.mjs';

const body = 'You made an online payment of RM12.50 to SHOP.';
const draft = { kind: 'payment', amount: '12.50', currency: 'MYR', party: 'SHOP', accountSuffix: '', transferPeer: '', evidence: body, completed: true };
const json = (value, status = 200) => new Response(JSON.stringify(value), { status });
const request = (input = { body, title: 'Money Paid', source: 'Public Bank' }, auth = 'Bearer test') => new Request('https://example.test', {
  method: 'POST', headers: { Authorization: auth, 'Content-Type': 'application/json' }, body: JSON.stringify(input),
});
function harness({ quota = true, authStatus = 200, anonymous = false, quotaStatus = 200, modelStatus = 200, finish = 'STOP', value = draft, env = {}, modelText } = {}) {
  const calls = [];
  return { calls, env: name => ({ SUPABASE_URL: 'https://example.test', SUPABASE_ANON_KEY: 'public', GEMINI_API_KEY: 'private', GEMINI_BANK_MODEL: 'gemini-test', ...env })[name],
    fetch: async (url, options) => {
      calls.push({ url, options });
      if (url.endsWith('/auth/v1/user')) return json({ id: 'test', is_anonymous: anonymous }, authStatus);
      if (url.endsWith('/claim_bank_analysis')) return json(quota, quotaStatus);
      return json({ candidates: [{ finishReason: finish, content: { parts: [{ text: modelText ?? JSON.stringify(value) }] } }] }, modelStatus);
    } };
}
test('auth and non-anonymous account are required before processing input', async () => {
  const missing = harness(); assert.equal((await handleBankNotification(request({}, ''), missing)).status, 401); assert.equal(missing.calls.length, 0);
  for (const options of [{ authStatus: 401 }, { anonymous: true }]) {
    const deps = harness(options); assert.equal((await handleBankNotification(request(), deps)).status, 401); assert.equal(deps.calls.length, 1);
  }
});
test('configuration, invalid input and quota failures do not call Gemini', async () => {
  const missing = harness({ env: { GEMINI_BANK_MODEL: '' } });
  assert.equal((await handleBankNotification(request(), missing)).status, 503); assert.equal(missing.calls.length, 0);
  for (const input of [null, {}, { body: 'a'.repeat(8001), title: '', source: '' }]) {
    const deps = harness(); assert.equal((await handleBankNotification(request(input), deps)).status, 400); assert.equal(deps.calls.length, 1);
  }
  for (const [options, status] of [[{ quota: false }, 429], [{ quotaStatus: 404 }, 503]]) {
    const deps = harness(options); assert.equal((await handleBankNotification(request(), deps)).status, status); assert.equal(deps.calls.length, 2);
  }
});
test('returns whitelisted fields only and sends no account IDs or balances to Google', async () => {
  const deps = harness({ value: { ...draft, private: 'not exposed' } });
  const response = await handleBankNotification(request({ body, title: 'Money Paid', source: 'Public Bank', balance: 99999, accounts: ['private'] }), deps);
  assert.deepEqual(await response.json(), draft);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  const sent = JSON.parse(deps.calls[2].options.body);
  assert.deepEqual(JSON.parse(sent.contents[0].parts[1].text), { body, title: 'Money Paid', source: 'Public Bank' });
});
test('rejects invented evidence, malformed fields and truncated output', async () => {
  for (const value of [{ ...draft, evidence: 'invented' }, { ...draft, party: 'invented' }, { ...draft, kind: 'withdrawEverything' },
    { ...draft, completed: 'yes' }, { ...draft, accountSuffix: '1234567890' }, { ...draft, amount: '-12.50' }]) {
    assert.equal((await handleBankNotification(request(), harness({ value }))).status, 422);
  }
  assert.equal((await handleBankNotification(request(), harness({ finish: 'MAX_TOKENS' }))).status, 422);
  assert.equal((await handleBankNotification(request(), harness({ modelText: 'not JSON' }))).status, 422);
});
test('upstream errors never leak provider response or credentials', async () => {
  for (const modelStatus of [400, 403, 404, 429, 500]) {
    const response = await handleBankNotification(request(), harness({ modelStatus }));
    assert.equal(response.status, modelStatus === 429 ? 429 : 502);
    assert.deepEqual(await response.json(), { error: 'analysis_unavailable' });
  }
});
