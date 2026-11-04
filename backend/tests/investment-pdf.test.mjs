import {test} from 'node:test';
import assert from 'node:assert/strict';
import {officialPDF} from '../../supabase/functions/investment-research/pdf.mjs';
import {collectOfficialEvidence,officialSources} from '../../supabase/functions/investment-research/official.mjs';
import {readFile} from 'node:fs/promises';
const response = () => new Response('%PDF-1.7 test', {headers:{'Content-Type':'application/pdf'}});
function parser(pages) {
  const state = {destroyed:false};
  state.load = async () => ({getDocumentProxy:async (_bytes, options) => {
    assert.equal(options.isEvalSupported,false);
    assert.equal(options.useWorkerFetch,false);
    return {numPages:pages.length, loadingTask:{destroy:async()=>{state.destroyed=true;}}, getPage:async n=>({cleanup(){},getTextContent:async()=>({items:[{str:pages[n-1],hasEOL:true}]})})};
  }});
  return state;
}
test('PDF keeps page markers, rejects scans/oversize and releases parser', async()=>{
  let p=parser(['Company financial results 2026','Revenue 100 profit 20 quarter']);
  const text=await officialPDF('https://official.test/report.pdf',async(_u,o)=>{assert.equal(o.redirect,'error');return response();},p.load);
  assert.match(text,/PDF page 2\/2/); assert.ok(p.destroyed);
  for(const pages of [[''],Array(61).fill('A'.repeat(25)),['a'.repeat(60001)]]){
    p=parser(pages);await assert.rejects(officialPDF('x',async()=>response(),p.load));assert.ok(p.destroyed);
  }
  for(const body of ['not a pdf','%PDF-'+ 'x'.repeat(8000000)]){
    await assert.rejects(officialPDF('x',async()=>new Response(body,{headers:{'Content-Type':'application/pdf'}}),()=>{throw Error('must not load');}));
  }
  await assert.rejects(officialPDF('x',async()=>new Response('%PDF-', {headers:{'Content-Type':'text/html'}})));
});
test('PDF official path verifies identity and labels extraction format',async()=>{
  const text='IJM CORPORATION BERHAD 2026 Revenue profit quarter '+ 'Financial information. '.repeat(30);
  let p=parser([text]);
  const evidence=await collectOfficialEvidence(['MYX:IJM'],async u=>{assert.equal(u,officialSources['MYX:IJM'].url);return response();},p.load);
  assert.equal(evidence[0].format,'pdf-text'); assert.match(evidence[0].text,/PDF page 1/);
  p=parser([text.replace('IJM CORPORATION BERHAD','Other Company')]);
  await assert.rejects(collectOfficialEvidence(['MYX:IJM'],async()=>response(),p.load),/source_unavailable/);
});
test('app automatic coverage matches server allowlist',async()=>{
  const swift=await readFile(new URL('../../YueJi/InvestmentViews.swift',import.meta.url),'utf8');
  const line=swift.split('\n').find(s=>s.includes('var hasOfficialImporter:'));
  const symbols=[...line.matchAll(/"([A-Z]+:[A-Z0-9]+)"/g)].map(m=>m[1]);
  assert.deepEqual(symbols.sort(),Object.keys(officialSources).sort());
});
