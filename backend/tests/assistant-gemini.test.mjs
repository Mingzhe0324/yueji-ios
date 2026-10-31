import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleAssistant, cleanResult, validInput } from '../../supabase/functions/assistant-gemini/handler.mjs';
const input = { mode: 'classify', text: '洗衣液', categories: ['餐饮', '购物', '其他'] };
const request = (body = input, auth = 'Bearer test') => new Request('https://test.invalid', { method: 'POST', headers: { Authorization: auth, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
const json = (body, status = 200) => new Response(JSON.stringify(body), { status });
function harness({ anonymous = false, quota = true, value = { category: '购物' }, finish = 'STOP', status = 200, configured = true } = {}) {
  const calls = [], logs = [];
  return { calls, logs, log: value => logs.push(value), env: k => ({ SUPABASE_URL: 'https://test.invalid', SUPABASE_ANON_KEY: 'public', GEMINI_API_KEY: 'secret', GEMINI_ASSISTANT_MODEL: configured ? 'gemini-test' : '' })[k],
    fetch: async (url, options) => {
      calls.push({ url, options });
      if (url.endsWith('/auth/v1/user')) return json({ id: 'test', is_anonymous: anonymous });
      if (url.endsWith('/claim_assistant_request')) return json(quota);
      return json({ candidates: [{ finishReason: finish, content: { parts: [{ text: JSON.stringify(value) }] } }] }, status);
    } };
}
test('auth, anonymous users, missing config and quota block model calls', async () => {
  for (const [deps, auth, expected, count] of [[harness(), '', 401, 0], [harness({ anonymous: true }), 'Bearer x', 401, 1], [harness({ configured: false }), 'Bearer x', 503, 0], [harness({ quota: false }), 'Bearer x', 429, 2]]) {
    assert.equal((await handleAssistant(request(input, auth), deps)).status, expected);
    assert.equal(deps.calls.length, count);
  }
});
test('input bounds and mode allowlist reject malformed requests', async () => {
  for (const body of [null, {}, { ...input, mode: '__proto__' }, { ...input, text: '' }, { ...input, text: 'x'.repeat(1001) }, { ...input, categories: ['购物', '购物'] }, { ...input, categories: [] }]) {
    assert.ok(!validInput(body));
    const deps = harness(); assert.equal((await handleAssistant(request(body), deps)).status, 400); assert.equal(deps.calls.length, 1);
  }
});
test('only explicitly allowed payload fields reach the model', async () => {
  const deps = harness({ value: { category: '购物', balance: 999 } });
  const response = await handleAssistant(request({ ...input, balance: 123, ledger: ['private'] }), deps);
  assert.deepEqual(await response.json(), { category: '购物' });
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  const sent = JSON.parse(deps.calls[2].options.body);
  assert.deepEqual(JSON.parse(sent.contents[0].parts[0].text), { text: input.text, categories: input.categories });
});
test('unknown category, truncation and upstream failures cannot be accepted', async () => {
  assert.equal((await handleAssistant(request(), harness({ value: { category: 'invented' } }))).status, 422);
  assert.equal((await handleAssistant(request(), harness({ finish: 'MAX_TOKENS' }))).status, 422);
  for (const [status, error] of [[400, 'model_request_rejected'], [401, 'model_access_denied'], [403, 'model_access_denied'], [404, 'model_unavailable'], [429, 'model_rate_limit'], [500, 'model_server_error'], [503, 'model_overloaded']]) {
    const deps = harness({ status });
    const response = await handleAssistant(request(), deps);
    assert.equal(response.status, status === 429 ? 429 : 502);
    assert.deepEqual(await response.json(), { error });
    assert.deepEqual(deps.logs, [{ event: 'assistant_failure', stage: 'gemini', error, upstream_status: status }]);
  }
});
test('timeout, transport and malformed responses have distinct safe diagnostics', async () => {
  for (const [scenario, expected, stage] of [['timeout', 'assistant_timeout', 'gemini'], ['network', 'assistant_connection_failed', 'gemini'], ['json', 'invalid_model_response', 'gemini_response']]) {
    const deps = harness(), original = deps.fetch;
    deps.fetch = async (url, options) => {
      if (!url.includes('googleapis.com')) return original(url, options);
      if (scenario === 'json') return new Response('private upstream content');
      if (scenario === 'timeout') throw new DOMException('private input and secret', 'TimeoutError');
      throw new Error('private input and secret');
    };
    const response = await handleAssistant(request(), deps);
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: expected });
    assert.deepEqual(deps.logs, [{ event: 'assistant_failure', stage, error: expected }]);
  }
});
test('entry amounts must match a single explicit number; fabricated name and sums fail', () => {
  const entry = { ...input, mode: 'entry', text: '午餐 RM18.50' };
  const value = { name: '午餐', amount: '18.50', category: '餐饮' };
  assert.deepEqual(cleanResult(value, entry), value);
  assert.equal(cleanResult({ ...value, amount: '20.00' }, entry), null);
  assert.equal(cleanResult({ ...value, name: 'invented' }, entry), null);
  assert.equal(cleanResult(value, { ...entry, text: '午餐 RM18.50 饮料 RM2.00' }), null);
  assert.equal(cleanResult(value, { ...entry, text: '午餐 USD18.50' }), null);
  assert.equal(cleanResult(value, { ...entry, text: '午餐 18.50' }), null);
});
test('query produces only a supported intent/filter, never invented figures', () => {
  const query = { ...input, mode: 'query' };
  assert.deepEqual(cleanResult({ intent: 'summary', category: '', total: 1000 }, query), { intent: 'summary', category: '' });
  assert.equal(cleanResult({ intent: 'delete', category: '' }, query), null);
  assert.equal(cleanResult({ intent: 'category', category: '' }, query), null);
});
