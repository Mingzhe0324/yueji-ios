import { test } from 'node:test';
import assert from 'node:assert/strict';
import { collectOfficialEvidence, reportLinks, pageText, evidenceFragments, evidenceReport, dimensions } from '../../supabase/functions/investment-research/official.mjs';
import { handleResearch } from '../../supabase/functions/investment-research/handler.mjs';
import { reportKey, validCachedReport } from '../../supabase/functions/investment-research/cache.mjs';
const symbol = 'MYX:99SMART';
const quote = 'Revenue 2026 quarter profit 99 Speed Mart';
const html = `<html><h1>99 Speed Mart</h1><p>${quote}</p><table><tr><th>2026</th><th>2025</th></tr><tr><td>Revenue</td><td>100</td></tr></table><p>${'Financial information. '.repeat(35)}</p></html>`;
const source = { id:'S1',symbol,company:'99 Speed Mart',url:'https://99speedmart.com.my/financial-information/',fetchedAt:'2026-11-04T00:00:00Z',text:pageText(html) };
const company = () => ({symbol,summary:'示例分析',period:'2026',action:'consider',conditions:'先核实估值，盈利恶化时重新评估',missing:'现价与风险资料',dimensions:dimensions.map(key=>({key,score:15,reason:'测试依据',evidence:[{sourceId:'S1',quote}]}))});
const candidate = c => ({finishReason:'STOP',content:{parts:[{text:JSON.stringify({companies:[c]})}]}});
const json = value => new Response(JSON.stringify(value));

const indexedCompany = () => {const c=company();for(const d of c.dimensions)d.evidence=[{sourceId:'S1',fragmentId:'F1'}];return c;};
test('numbered citations resolve exact source text and reject unknown, cross-company and supplied quotes', () => {
 const c=indexedCompany();
 const report=evidenceReport(candidate(c),[symbol],[source],{indexed:true});
 assert.equal(report.assessments[0].dimensions[0].evidence[0].quote,source.text);
 for(const change of [c=>c.dimensions[0].evidence[0].fragmentId='F999',c=>c.dimensions[0].evidence[0].sourceId='S2',c=>c.dimensions[0].evidence[0].quote='fabricated']){
  const bad=indexedCompany();change(bad);assert.equal(evidenceReport(candidate(bad),[symbol],[source],{indexed:true}),null);
 }
 assert.equal(evidenceReport(candidate(c),[symbol],[{...source,symbol:'NASDAQ:AAPL'}],{indexed:true}),null);
 const text='header | Revenue 2026 | 100 |\n'.repeat(200);
 const fragments=evidenceFragments(text);
 assert.ok(fragments.length>1);
 for(const f of fragments){assert.ok(text.includes(f.quote));assert.ok(f.quote.length<=1200);}
 assert.ok(fragments.at(-1).quote.endsWith('100 |\n'));
});

test('accepts whitespace-only citation differences and restores original text', () => {
  const original = 'Revenue\n2026\u00a0quarter   profit 99 Speed Mart';
  const result = evidenceReport(candidate(company()), [symbol], [{...source,text:original}]);
  assert.ok(result);
  assert.equal(result.assessments[0].dimensions[0].evidence[0].quote, original);
  const changed = company(); changed.dimensions[0].evidence[0].quote = quote.replace('2026', '2025');
  assert.equal(evidenceReport(candidate(changed), [symbol], [{...source,text:original}]), null);
  assert.equal(evidenceReport(candidate(company()), [symbol], [{...source,text:quote.replace('Revenue ', 'Revenue | ')}]), null);
});

test('accepts one JSON fence but rejects surrounding prose and reports incomplete output', () => {
  const value = candidate(company());
  const raw = value.content.parts[0].text;
  value.content.parts[0].text = '```json\n' + raw + '\n```';
  assert.ok(evidenceReport(value, [symbol], [source]));
  value.content.parts[0].text = 'Explanation\n' + raw;
  let reason;
  assert.equal(evidenceReport(value, [symbol], [source], {onReject:r=>reason=r}), null);
  assert.equal(reason, 'invalid_json');
  value.finishReason = 'MAX_TOKENS';
  assert.equal(evidenceReport(value, [symbol], [source], {onReject:r=>reason=r}), null);
  assert.equal(reason, 'incomplete_output');
});

test('CIMB income and TNB annual summary use source-specific period checks', async () => {
  for (const [ticker, body, required] of [
    ['MYX:CIMB', 'CIMB Group Holdings Berhad Total income profit second quarter ended 30 June 2026', 'second quarter ended 30 June 2026'],
    ['MYX:TENAGA', 'Tenaga Nasional Berhad Five-Year Group Financial Summary Revenue profit 2025', 'Five-Year Group Financial Summary']
  ]) {
    const fetcher = text => async () => new Response(`<p>${text}</p><p>${'Financial information. '.repeat(35)}</p>`, {headers:{'Content-Type':'text/html'}});
    const evidence = await collectOfficialEvidence([ticker], fetcher(body));
    assert.equal(evidence[0].symbol, ticker);
    assert.ok(evidence[0].scope.length > 20);
    await assert.rejects(collectOfficialEvidence([ticker], fetcher(body.replace(required, 'unrelated period'))), /source_unavailable/);
    await assert.rejects(collectOfficialEvidence([ticker], fetcher(body.replace(/CIMB Group Holdings Berhad|Tenaga Nasional Berhad/, 'Other Company'))), /source_unavailable/);
  }
});

test('cache key changes with evidence/model/order but not retrieval time; expires after 24h', async () => {
  const key=await reportKey([symbol],[source],'gemini-test');
  assert.equal(key,await reportKey([symbol],[{...source,fetchedAt:'later'}],'gemini-test'));
  assert.notEqual(key,await reportKey([symbol],[{...source,text:source.text+'new filing'}],'gemini-test'));
  assert.notEqual(key,await reportKey([symbol],[source],'gemini-other'));
  const now=Date.now(),value={symbol,symbols:[symbol],generatedAt:new Date(now).toISOString(),candidate:candidate(company())};
  assert.ok(validCachedReport(value,[symbol],now));
  assert.ok(!validCachedReport(value,[symbol],now+86400000));
  assert.ok(!validCachedReport(value,[symbol],now-1));
  assert.ok(!validCachedReport(value,['MYX:MAYBANK'],now));
});

test('cache hit revalidates citations, avoids quota/model and never trusts cached HTML', async () => {
  let forged=false;
  const calls=[];
  const deps={env:k=>({SUPABASE_URL:'https://test.invalid',SUPABASE_ANON_KEY:'anon',INVESTMENT_RESEARCH_USER_ID:'owner',GEMINI_RESEARCH_API_KEY:'key',GEMINI_RESEARCH_MODEL:'gemini-test',INVESTMENT_RESEARCH_CACHE:'true'})[k],fetch:async(u,o)=>{
    calls.push(u);
    if(u.endsWith('/auth/v1/user'))return json({id:'owner'});
    if(u.startsWith('https://99speedmart.com.my/'))return new Response(html,{headers:{'Content-Type':'text/html'}});
    if(u.endsWith('/read_investment_report')){
      const c=indexedCompany();if(forged)c.dimensions[0].evidence[0].fragmentId='F999';
      return json({symbol,symbols:[symbol],generatedAt:new Date().toISOString(),candidate:candidate(c),html:'<script>evil</script>'});
    }
    if(u.endsWith('/claim_investment_research'))return json(false);
    throw new Error('unexpected request');
  }};
  const request=()=>new Request('https://test.invalid',{method:'POST',headers:{Authorization:'Bearer user','Content-Type':'application/json'},body:JSON.stringify({symbols:[symbol]})});
  const result=await handleResearch(request(),deps);assert.equal(result.status,200);
  const value=await result.json();assert.equal(value.cached,true);assert.ok(!value.html.includes('<script>'));
  assert.equal(value.horizons.length,3);assert.ok(value.horizons.every(h=>h.status==='insufficient'));
  assert.ok(!calls.some(u=>u.includes('claim_')||u.includes('googleapis')));
  forged=true;calls.length=0;
  assert.equal((await handleResearch(request(),deps)).status,429);
  assert.ok(calls.some(u=>u.includes('claim_')));
});
test('HTML preserves table boundaries, strips executable content and rejects off-origin links', () => {
  assert.match(pageText(html), /Revenue \| 100 \|/);
  assert.equal(pageText('<script>bad</script><!--bad--><p>safe &amp; sound</p>'), 'safe & sound');
  const links = reportLinks(['https://evil.test/news.html/id/1','https://user:pass@maybank.listedcompany.com/news.html/id/2','/news.html/id/3','/news.html/id/3','/news.html/id/4','/news.html/id/5'].map(u=>`<a href="${u}">Quarterly Rpt On Consolidated Results</a>`).join(''), 'https://maybank.listedcompany.com/newsroom.html/cat/7648');
  assert.deepEqual(links,['https://maybank.listedcompany.com/news.html/id/3','https://maybank.listedcompany.com/news.html/id/4']);
});
test('official importer fetches only mapped pages with no redirects and fails on challenges and oversized sources', async () => {
  const calls=[];
  const evidence=await collectOfficialEvidence([symbol],async(u,o)=>{calls.push([u,o]);return new Response(html,{headers:{'Content-Type':'text/html'}});});
  assert.equal(evidence[0].symbol,symbol); assert.equal(calls.length,1); assert.equal(calls[0][1].redirect,'error');
  await assert.rejects(collectOfficialEvidence(['MYX:UNKNOWN'],async()=>{throw new Error('should not fetch');}),/unsupported_source/);
  for (const body of ['<html>Access denied</html>', 'x'.repeat(1500001)]) {
    await assert.rejects(collectOfficialEvidence([symbol],async()=>new Response(body,{headers:{'Content-Type':'text/html'}})));
  }
});
test('overall stays absent without valuation and risk data; model cannot force a buy rating', () => {
  const report=evidenceReport(candidate(company()),[symbol],[source]);
  assert.equal(report.assessments[0].overall,null);
  assert.equal(report.assessments[0].action,'insufficient');
  assert.equal(report.assessments[0].coverage,3);
  assert.match(report.text,/不是上涨概率/); assert.match(report.text,/https:\/\/99speedmart/);
  assert.ok(!Object.hasOwn(report.sources[0],'text'));
});

test('new importers keep company identity, complete quarterly sections and annual scope', async () => {
  const section = (n) => `<h2>${n} Quarter Results For The Financial Period Ended 31 July 2026</h2><p>Gamuda Berhad Revenue RM 100 profit RM 10 ${'Financial results. '.repeat(40)}</p>`;
  const gamuda = `<h1>Navigation</h1>${section('4th')}${section('3rd')}${section('2nd')}<p>${'old archive '.repeat(4000)}</p>`;
  const fetchHTML = body => async () => new Response(body, {headers:{'Content-Type':'text/html'}});
  const g = await collectOfficialEvidence(['MYX:GAMUDA'], fetchHTML(gamuda));
  assert.match(g[0].text, /4th Quarter/);
  assert.match(g[0].text, /3rd Quarter/);
  assert.ok(!g[0].text.includes('2nd Quarter'));
  assert.ok(!g[0].text.includes('old archive'));
  assert.match(g[0].scope, /前两个/);
  const annual = `<h1>Hong Leong Bank</h1><p>Financial year ended 30 June 2026. Loans and financing profit. ${'Annual results. '.repeat(45)}</p>`;
  const h = await collectOfficialEvidence(['MYX:HLBANK'], fetchHTML(annual));
  assert.match(h[0].scope, /固定 FY2026/);
  await assert.rejects(collectOfficialEvidence(['MYX:HLBANK'], fetchHTML(annual.replace('Hong Leong Bank', 'Apple'))), /source_unavailable/);
  await assert.rejects(collectOfficialEvidence(['MYX:GAMUDA'], fetchHTML(section('4th'))), /source_unavailable/);
});
test('rejects invented, cross-company and missing citations, duplicate dimensions and unfinished model output', () => {
  for (const change of [c=>c.dimensions[0].evidence[0].quote='fabricated evidence',c=>c.dimensions[0].evidence=[],c=>c.dimensions[0].evidence[0].sourceId='S9',c=>c.dimensions[0].score=21,c=>c.dimensions[0].key='risk',c=>c.symbol='MYX:MAYBANK']) {
    const c=company();change(c);assert.equal(evidenceReport(candidate(c),[symbol],[source]),null);
  }
  assert.equal(evidenceReport({...candidate(company()),finishReason:'MAX_TOKENS'},[symbol],[source]),null);
  assert.equal(evidenceReport(candidate(company()),[symbol],[{...source,symbol:'MYX:MAYBANK'}]),null);
});
test('default route imports evidence without Google Search, strips client documents and safely renders output', async () => {
  const calls=[];
  const c=indexedCompany(); c.summary='<script>example</script>';
  const deps={env:k=>({SUPABASE_URL:'https://test.invalid',SUPABASE_ANON_KEY:'anon',INVESTMENT_RESEARCH_USER_ID:'owner',GEMINI_RESEARCH_API_KEY:'key',GEMINI_RESEARCH_MODEL:'gemini-test'})[k],fetch:async(u,o)=>{
    calls.push([u,o]);
    if(u.endsWith('/auth/v1/user'))return json({id:'owner'});
    if(u.endsWith('/claim_investment_research'))return json(true);
    if(u.startsWith('https://99speedmart.com.my/'))return new Response(html,{headers:{'Content-Type':'text/html'}});
    return json({candidates:[candidate(c)]});
  }};
  const request=(symbols)=>new Request('https://test.invalid',{method:'POST',headers:{Authorization:'Bearer user','Content-Type':'application/json'},body:JSON.stringify({symbols,ledger:'private',evidence:[{url:'https://evil.test'}]})});
  const response=await handleResearch(request([symbol]),deps); assert.equal(response.status,200);
  const value=await response.json(); assert.match(value.html,/&lt;script&gt;/); assert.ok(!value.html.includes('<script>'));
  const sent=JSON.parse(calls.at(-1)[1].body); assert.equal(sent.tools,undefined);
  assert.ok(!JSON.stringify(sent).includes('private'));assert.ok(!JSON.stringify(sent).includes('evil.test'));
  assert.match(JSON.parse(sent.contents[0].parts[0].text).evidence[0].fragments[0].quote,/Revenue/);
  calls.length=0;
  const unsupported=await handleResearch(request(['MYX:PBBANK']),deps);
  assert.equal(unsupported.status,422);assert.equal(calls.length,1);
});
