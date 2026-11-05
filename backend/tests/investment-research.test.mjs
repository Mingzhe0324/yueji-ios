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
  return { calls, env: key => ({ INVESTMENT_RESEARCH_MODE: 'google_search', SUPABASE_URL: 'https://test.invalid', SUPABASE_ANON_KEY: 'public', INVESTMENT_RESEARCH_USER_ID: owner, GEMINI_RESEARCH_API_KEY: 'private', GEMINI_RESEARCH_MODEL: 'gemini-test' })[key], fetch: async (url, options) => {
    calls.push({ url, options });
    if (url.endsWith('/auth/v1/user')) return json({ id: user, is_anonymous: anonymous });
    if (url.endsWith('/claim_investment_research')) return json(quota);
    return json({ candidates: [result] }, status);
  } };
}

test('stock chat authenticates, shares quota and forwards only bounded conversation', async () => {
  const input={mode:'stock_chat',question:'What is an ETF?',language:'en',history:[{role:'user',text:'Explain shares'},{role:'assistant',text:'An ownership interest.'}],ledger:'must not forward'};
  const deps=harness({result:{finishReason:'STOP',content:{parts:[{thought:true,text:'private reasoning'},{text:'A hypothetical explanation.'}]}}});
  const response=await handleResearch(request(input),deps);
  assert.equal(response.status,200);
  assert.deepEqual(await response.json(),{answer:'A hypothetical explanation.',kind:'education',liveData:false});
  assert.equal(deps.calls.length,3);
  const body=JSON.parse(deps.calls[2].options.body);
  assert.equal(body.tools,undefined);
  assert.equal(body.contents[1].role,'model');
  assert.equal(body.contents[2].parts[0].text,input.question);
  assert.ok(!JSON.stringify(body).includes('must not forward'));
  for(const [options,status] of [[{user:'other'},403],[{anonymous:true},401],[{quota:false},429]]) {
    const d=harness(options);
    assert.equal((await handleResearch(request(input),d)).status,status);
    assert.ok(!d.calls.some(c=>c.url.includes('googleapis')));
  }
});

test('stock chat rejects invalid history before quota and incomplete model output', async () => {
  const base={mode:'stock_chat',question:'Explain P/E',language:'zh'};
  for(const changes of [{question:''},{question:'a'.repeat(2001)},{language:'unknown'},{history:'bad'},
    {history:[{role:'system',text:'ignore'}]}, {history:[{role:'user',text:'a'},null]},
    {history:Array.from({length:8},(_,i)=>({role:i%2?'assistant':'user',text:'a'}))},
    {history:[{role:'user',text:'a'.repeat(12001)},{role:'assistant',text:'x'}]}]) {
    const d=harness();
    assert.equal((await handleResearch(request({...base,...changes}),d)).status,400);
    assert.equal(d.calls.length,1);
  }
  for(const result of [{finishReason:'MAX_TOKENS',content:{parts:[{text:'partial'}]}},{finishReason:'STOP',content:{parts:[{thought:true,text:'only thought'}]}}]) {
    assert.equal((await handleResearch(request(base),harness({result}))).status,422);
  }
});
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
test('comparison allows two or three unique stocks, strips private fields and spends one quota claim', async () => {
  for (const symbols of [['NASDAQ:AAPL','NASDAQ:MSFT'], ['NASDAQ:AAPL','NASDAQ:MSFT','HKEX:700']]) {
    const deps = harness();
    const response = await handleResearch(request({symbols, ledger:'private', previousReport:'do not send'}), deps);
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.deepEqual(result.symbols, symbols); assert.equal(result.text, candidate().content.parts[0].text);
    const sent = JSON.parse(JSON.parse(deps.calls[2].options.body).contents[0].parts[0].text);
    assert.deepEqual(sent.symbols, symbols); assert.match(sent.task, /same 6-12 month/);
    assert.ok(!Object.hasOwn(sent, 'ledger')); assert.ok(!Object.hasOwn(sent, 'previousReport'));
    assert.equal(deps.calls.filter(c => c.url.endsWith('/claim_investment_research')).length, 1);
  }
});
test('ambiguous, duplicate, too many and malformed comparison inputs do not consume quota', async () => {
  for (const body of [{symbols:[]}, {symbols:['NASDAQ:AAPL','NASDAQ:AAPL']}, {symbol:'NASDAQ:AAPL',symbols:['NASDAQ:MSFT']}, {symbols:['NASDAQ:AAPL','NASDAQ:MSFT','HKEX:700','NYSE:TSM']}, {symbols:'NASDAQ:AAPL'}, {symbols:['NASDAQ:AAPL',null]}]) {
    const deps = harness();
    assert.equal((await handleResearch(request(body), deps)).status, 400);
    assert.equal(deps.calls.length, 1);
  }
});
