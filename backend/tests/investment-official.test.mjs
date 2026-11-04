import { test } from 'node:test';
import assert from 'node:assert/strict';
import { collectOfficialEvidence, reportLinks, pageText, evidenceReport, dimensions } from '../../supabase/functions/investment-research/official.mjs';
import { handleResearch } from '../../supabase/functions/investment-research/handler.mjs';
const symbol = 'MYX:99SMART';
const quote = 'Revenue 2026 quarter profit 99 Speed Mart';
const html = `<html><h1>99 Speed Mart</h1><p>${quote}</p><table><tr><th>2026</th><th>2025</th></tr><tr><td>Revenue</td><td>100</td></tr></table><p>${'Financial information. '.repeat(35)}</p></html>`;
const source = { id:'S1',symbol,company:'99 Speed Mart',url:'https://99speedmart.com.my/financial-information/',fetchedAt:'2026-11-04T00:00:00Z',text:pageText(html) };
const company = () => ({symbol,summary:'示例分析',period:'2026',action:'consider',conditions:'先核实估值，盈利恶化时重新评估',missing:'现价与风险资料',dimensions:dimensions.map(key=>({key,score:15,reason:'测试依据',evidence:[{sourceId:'S1',quote}]}))});
const candidate = c => ({finishReason:'STOP',content:{parts:[{text:JSON.stringify({companies:[c]})}]}});
const json = value => new Response(JSON.stringify(value));
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
  const c=company(); c.summary='<script>example</script>';
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
  assert.match(JSON.parse(sent.contents[0].parts[0].text).evidence[0].text,/Revenue/);
  calls.length=0;
  const unsupported=await handleResearch(request(['MYX:PBBANK']),deps);
  assert.equal(unsupported.status,422);assert.equal(calls.length,1);
});
