import {test} from 'node:test';
import assert from 'node:assert/strict';
import {importedEvidence} from '../../supabase/functions/investment-research/imported.mjs';
import {evidenceReport,dimensions} from '../../supabase/functions/investment-research/official.mjs';
import {handleResearch} from '../../supabase/functions/investment-research/handler.mjs';
const symbol='MYX:TEST';
const now=Date.parse('2026-11-05T00:00:00Z');
const csv='symbol,currency,date,open,high,low,close,volume\n'+Array.from({length:20},(_,i)=>`${symbol},MYR,2026-10-${String(i+12).padStart(2,'0')},10,12,9,11,100`).join('\n');
const input={csv,source:'User licensed export, adjustment unknown',notes:'Financial statements and explicit risk disclosure. '.repeat(15)};
const candidate=()=>({finishReason:'STOP',content:{parts:[{text:JSON.stringify({companies:[{symbol,summary:'Imported analysis',period:'2026-10-31',action:'consider',conditions:'Entry and exit conditions only',missing:'No live quotes',dimensions:dimensions.map(key=>({key,score:12,reason:'Imported evidence',evidence:[{sourceId:'U2',quote:'Financial statements and explicit risk disclosure.'}]}))}]})}]}});
test('imports validate OHLCV identity, date, currency and bounds; deterministic averages',()=>{
 const value=importedEvidence(input,symbol,now);
 assert.equal(value.metrics.sma20,11);assert.equal(value.metrics.sma50,null);assert.equal(value.metrics.count,20);
 assert.equal(value.recent,true);assert.equal(value.hasFinancials,true);
 assert.equal(importedEvidence(input,symbol,now+10*86400000).recent,false);
 for(const bad of [csv.replace('MYX:TEST,','MYX:OTHER,'),csv.replace(',MYR,',',USD,'),csv.replace('2026-10-12','2026-02-30'),csv.replace(',10,12,9,11,',',10,8,9,11,'),csv.replace(',100',',NaN'),csv+'\n'+csv.split('\n')[1],csv.replace('2026-10-31','2027-01-01')]) {
   assert.throws(()=>importedEvidence({...input,csv:bad},symbol,now),/invalid_import/);
 }
 assert.throws(()=>importedEvidence({...input,source:''},symbol,now));
 assert.throws(()=>importedEvidence({...input,notes:'x'.repeat(30001)},symbol,now));
});
test('manual research is labeled unverified; missing or stale inputs cannot force total; exact quotes required',()=>{
 const value=importedEvidence(input,symbol,now);
 const supported=candidate();
 const parsed=JSON.parse(supported.content.parts[0].text);
 parsed.companies[0].dimensions.find(d=>d.key==='valuation').evidence.push({sourceId:'U1',quote:'User-declared source:'});
 supported.content.parts[0].text=JSON.stringify(parsed);
 const report=evidenceReport(supported,[symbol],value.evidence,{imported:true,allowFullScore:true});
 assert.equal(report.assessments[0].overall,60);
 assert.match(report.text,/用户导入/);assert.doesNotMatch(report.text,/基于自动获取的官方/);
 assert.equal(report.horizons.length,0);
 assert.equal(evidenceReport(candidate(),[symbol],value.evidence,{imported:true,allowFullScore:false}).assessments[0].overall,null);
 const bad=candidate();bad.content.parts[0].text=bad.content.parts[0].text.replace('Financial statements and explicit risk disclosure.','Fabricated source quote not supplied');
 assert.equal(evidenceReport(bad,[symbol],value.evidence,{imported:true,allowFullScore:true}),null);
 const priceOnly=candidate();priceOnly.content.parts[0].text=priceOnly.content.parts[0].text.replaceAll('U2','U1').replaceAll('Financial statements and explicit risk disclosure.','User-declared source:');
 assert.equal(evidenceReport(priceOnly,[symbol],value.evidence,{imported:true,allowFullScore:true}).assessments[0].overall,null);
});
test('manual route uses auth and quota, no official lookup or cloud cache, rejects invalid files before quota',async()=>{
 const calls=[];const json=v=>new Response(JSON.stringify(v));
 const deps={env:k=>({SUPABASE_URL:'https://test.invalid',SUPABASE_ANON_KEY:'anon',INVESTMENT_RESEARCH_USER_ID:'owner',GEMINI_RESEARCH_API_KEY:'key',GEMINI_RESEARCH_MODEL:'gemini-test',INVESTMENT_RESEARCH_CACHE:'true'})[k],fetch:async(u,o)=>{
 calls.push(u);
 if(u.endsWith('/auth/v1/user'))return json({id:'owner'});
 if(u.endsWith('/claim_investment_research'))return json(true);
 if(u.includes('googleapis.com')){assert.match(o.body,/untrusted evidence/);return json({candidates:[candidate()]});}
 throw new Error('unexpected fetch');}};
 const req=imported=>new Request('https://test.invalid',{method:'POST',headers:{Authorization:'Bearer user','Content-Type':'application/json'},body:JSON.stringify({symbols:[symbol],imported})});
 assert.equal((await handleResearch(req(input),deps)).status,200);
 assert.equal(calls.length,3);
 calls.length=0;assert.equal((await handleResearch(req({...input,csv:'bad'}),deps)).status,400);assert.equal(calls.length,1);
});
