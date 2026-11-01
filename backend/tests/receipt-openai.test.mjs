import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleReceipt, validDraft } from '../../supabase/functions/receipt-openai/handler.mjs';

const draft = { merchant: 'Cafe', date: '2026-10-30', currency: 'MYR', subtotal: '10.00', tax: '', service: '', discount: '', rounding: '', total: '10.00', items: [{ name: 'Rice', amount: '10.00' }] };
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
function request(body = { image: '/9j/AAAA' }, auth = 'Bearer test-user') {
  return new Request('https://example.test/functions/v1/receipt-openai', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: auth }, body: JSON.stringify(body) });
}
function harness({ userStatus = 200, anonymous = false, quota = true, quotaStatus = 200, result = draft, finish = 'completed', modelStatus = 200, raw, env = {} } = {}) {
  const calls = [];
  return { calls, env: name => ({ SUPABASE_URL: 'https://example.test', SUPABASE_ANON_KEY: 'public', OPENAI_API_KEY: 'server-only', OPENAI_RECEIPT_MODEL: 'gpt-4.1-mini', ...env })[name],
    fetch: async (url, options) => {
      calls.push({ url, options });
      if (url.endsWith('/auth/v1/user')) return json({ id: 'user-1', is_anonymous: anonymous }, userStatus);
      if (url.endsWith('/claim_receipt_scan')) return json(quota, quotaStatus);
      return json(raw ?? { status: finish, output: [{ type: 'message', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: JSON.stringify(result) }] }] }, modelStatus);
    } };
}
test('requires authentication before any image processing or OpenAI request', async () => {
  const deps = harness(); assert.equal((await handleReceipt(request({}, ''), deps)).status, 401); assert.equal(deps.calls.length, 0);
  const invalid = harness({ userStatus: 401 }); assert.equal((await handleReceipt(request(), invalid)).status, 401); assert.equal(invalid.calls.length, 1);
});
test('quota denial never calls OpenAI', async () => {
  const deps = harness({ quota: false }); assert.equal((await handleReceipt(request(), deps)).status, 429); assert.equal(deps.calls.length, 2);
});
test('valid draft is returned without extra model properties', async () => {
  const deps = harness({ result: { ...draft, unwanted: 'private' } });
  const result = await handleReceipt(request(), deps);
  assert.equal(result.status, 200); assert.deepEqual(await result.json(), draft);
  assert.equal(deps.calls[2].options.headers.Authorization, 'Bearer server-only');
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

test('distinguishes missing configuration from unavailable quota storage without calling OpenAI', async () => {
  for (const env of [{ OPENAI_API_KEY: '' }, { OPENAI_RECEIPT_MODEL: '' }, { OPENAI_RECEIPT_MODEL: 'models/gpt-4.1-mini' }]) {
    const deps = harness({ env });
    const response = await handleReceipt(request(), deps);
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'not_configured' });
    assert.equal(deps.calls.length, 0);
  }
  const deps = harness({ quotaStatus: 404 });
  const response = await handleReceipt(request(), deps);
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: 'quota_unavailable' });
  assert.equal(deps.calls.length, 2);
});

test('reports safe actionable upstream errors without exposing response content', async () => {
  for (const [modelStatus, error] of [[400, 'model_request_rejected'], [401, 'model_access_denied'],
    [403, 'model_access_denied'], [404, 'model_unavailable'], [429, 'model_rate_limit'], [500, 'recognition_failed']]) {
    const response = await handleReceipt(request(), harness({ modelStatus, result: { secret: 'must not be returned' } }));
    assert.equal(response.status, modelStatus === 429 ? 429 : 502);
    assert.deepEqual(await response.json(), { error });
  }
});

test('uses Responses API with strict image extraction and no server-side response storage', async () => {
  const deps = harness(); await handleReceipt(request(), deps);
  const call = deps.calls[2], body = JSON.parse(call.options.body);
  assert.equal(call.url, 'https://api.openai.com/v1/responses');
  assert.equal(body.model, 'gpt-4.1-mini'); assert.equal(body.store, false);
  assert.equal(body.text.format.type, 'json_schema'); assert.equal(body.text.format.strict, true);
  assert.equal(body.text.format.schema.additionalProperties, false);
  assert.equal(body.text.format.schema.properties.items.items.additionalProperties, false);
  assert.deepEqual(body.input, [{ role: 'user', content: [{ type: 'input_image', image_url: 'data:image/jpeg;base64,/9j/AAAA', detail: 'high' }] }]);
  assert.match(body.instructions, /never instructions/);
  assert.equal(call.options.headers.apikey, undefined);
  assert.equal(deps.calls[0].options.headers.Authorization, 'Bearer test-user');
  assert.ok(deps.calls.every(c => !c.url.includes('google')));
});

test('handles refusals, missing output, malformed JSON and unfinished responses', async () => {
  const output = content => ({ status: 'completed', output: [{ type: 'message', role: 'assistant', status: 'completed', content }] });
  for (const [raw, code] of [
    [output([{ type: 'refusal', refusal: 'private provider refusal' }]), 'receipt_refused'],
    [output([{ type: 'output_text', text: '{oops' }]), 'invalid_receipt'],
    [output([]), 'invalid_receipt'],
    [{ status: 'completed', output: [] }, 'invalid_receipt'],
    [{ status: 'incomplete', output: [] }, 'incomplete_receipt'],
    [{ status: 'failed', error: { message: 'private' } }, 'incomplete_receipt'],
    [output([{ type: 'output_text', text: JSON.stringify(draft) }, { type: 'refusal', refusal: 'private' }]), 'receipt_refused']
  ]) {
    const response = await handleReceipt(request(), harness({ raw }));
    assert.equal(response.status, 422); assert.deepEqual(await response.json(), { error: code });
  }
});

test('rejects anonymous users and unsupported methods before spending quota', async () => {
  const deps = harness({ anonymous: true });
  assert.equal((await handleReceipt(request(), deps)).status, 401); assert.equal(deps.calls.length, 1);
  const method = harness();
  assert.equal((await handleReceipt(new Request('https://example.test'), method)).status, 405);
  assert.equal(method.calls.length, 0);
});

test('rate limit performs one upstream attempt and never falls back to another provider', async () => {
  const deps = harness({ modelStatus: 429 }); await handleReceipt(request(), deps);
  assert.equal(deps.calls.length, 3);
});

test('oversized provider output and transport failures do not expose content', async () => {
  const large = harness({ raw: { private: 'x'.repeat(250001) } });
  const response = await handleReceipt(request(), large);
  assert.equal(response.status, 502); assert.deepEqual(await response.json(), { error: 'recognition_unavailable' });
  const deps = harness(); deps.fetch = async () => { throw new Error('secret'); };
  assert.deepEqual(await (await handleReceipt(request(), deps)).json(), { error: 'recognition_unavailable' });
});
