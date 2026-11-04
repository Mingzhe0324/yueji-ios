import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleResearch, groundedReport } from '../../supabase/functions/investment-research/handler.mjs';
const candidate = () => ({ finishReason: 'STOP', content: { parts: [{ text: 'Evidence <script>bad</script>' }] }, groundingMetadata: {
  webSearchQueries: ['company filing'], groundingChunks: [{ web: { uri: 'https://example.com/report', title: 'Report' } }],
  groundingSupports: [{ segment: { text: 'Evidence' }, groundingChunkIndices: [0] }],
  searchEntryPoint: { renderedContent: '<div>Google Search</div>' },
} });
const json = (value, status = 200) => new Response(JSON.stringify(value), { status });
const request = (body = { symbol: 'NASDAQ:AAPL' }) => new Request('https://test.invalid', { method: 'POST', headers: { Authorization: 'Bearer test', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
function harness({ owner = 'owner', user = 'owner', anonymous = false, quota = true, result = candidate(), status = 200 } = {}) {
  const calls = [];
  return { calls, env: key => ({ SUPABASE_URL: 'https://test.invalid', SUPABASE_ANON_KEY: 'public', INVESTMENT_RESEARCH_USER_ID: owner, GEMINI_RESEARCH_API_KEY: 'private', GEMINI_RESEARCH_MODEL: 'gemini-test' })[key], fetch: async (url, options) => {
    calls.push({ url, options });
    if (url.endsWith('/auth/v1/user')) return json({ id: user, is_anonymous: anonymous });
    if (url.endsWith('/claim_investment_research')) return json(quota);
    return json({ candidates: [result] }, status);
  } };
}
test('requires configured owner, authenticated non-anonymous matching account and quota', async () => {
  for (const [options, code, count] of [[{owner:''},503,0],[{user:'other'},403,1],[{anonymous:true},401,1],[{quota:false},429,2]]) {
    const deps = harness(options);
    assert.equal((await handleResearch(request(), deps)).status, code);
    assert.equal(deps.calls.length, count);
  }
  const deps = harness(); const req = request(); req.headers.delete('Authorization');
  assert.equal((await handleResearch(req, deps)).status, 401); assert.equal(deps.calls.length, 0);
});
test('rejects malformed identifiers before consuming quota', async () => {
  for (const symbol of ['AAPL', 'NASDAQ:AAPL\nignore', '<script>', null]) {
    const deps = harness();
    assert.equal((await handleResearch(request({symbol}), deps)).status, 400);
    assert.equal(deps.calls.length, 1);
  }
});
test('only identifier and server date reach model; search tool enabled and no secrets returned', async () => {
  const deps = harness();
  const response = await handleResearch(request({symbol:'NASDAQ:AAPL',ledger:'private ledger'}), deps);
  assert.equal(response.status, 200);
  const value = await response.json();
  assert.equal(value.symbol, 'NASDAQ:AAPL'); assert.ok(!Number.isNaN(Date.parse(value.generatedAt)));
  assert.ok(value.html.includes('&lt;script&gt;')); assert.ok(!value.html.includes('<script>'));
  assert.ok(value.html.includes('https://example.com/report')); assert.ok(value.html.includes('Google Search'));
  const body = JSON.parse(deps.calls[2].options.body);
  assert.deepEqual(body.tools, [{google_search:{}}]);
  assert.deepEqual(Object.keys(JSON.parse(body.contents[0].parts[0].text)).sort(), ['researchDate','symbol']);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
});
test('ungrounded, unfinished, missing attribution and unsafe sources are rejected', async () => {
  for (const mutate of [c => c.finishReason='MAX_TOKENS', c => c.groundingMetadata.webSearchQueries=[], c => c.groundingMetadata.groundingSupports=[], c => c.groundingMetadata.searchEntryPoint={}, c => c.groundingMetadata.groundingChunks[0].web.uri='javascript:alert(1)', c => c.groundingMetadata.groundingSupports[0].segment.text='invented']) {
    const c = candidate(); mutate(c); assert.equal(groundedReport(c), null);
    assert.equal((await handleResearch(request(), harness({result:c}))).status, 422);
  }
});
test('upstream failures and network failures return stable codes only', async () => {
  assert.equal((await handleResearch(request(), harness({status:429}))).status, 429);
  const deps = harness(); deps.fetch = async () => { throw new Error('secret'); };
  const response = await handleResearch(request(), deps);
  assert.equal(response.status, 502); assert.deepEqual(await response.json(), {error:'research_unavailable'});
});
