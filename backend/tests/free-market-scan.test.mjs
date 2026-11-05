import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {directory,observePrices,providerJSON,buildReport} from '../../scripts/lib/free-market-scan.mjs';
const now=Date.parse('2026-11-05T12:00:00Z');
test('collector without a key exits before creating state or sending requests',()=>{
  const env={...process.env};delete env.EODHD_API_KEY;
  const run=spawnSync(process.execPath,['scripts/scan_free_markets.mjs'],{env,encoding:'utf8'});
  assert.equal(run.status,2);assert.match(run.stderr,/No request was made/);
  const demo=spawnSync(process.execPath,['scripts/scan_free_markets.mjs'],{env:{...env,EODHD_API_KEY:'demo'},encoding:'utf8'});
  assert.equal(demo.status,2);
});
const record={Code:'ABC',Name:'Example',Exchange:'NASDAQ',Type:'Common Stock',Currency:'USD'};
function bars(){return Array.from({length:70},(_,i)=>({date:new Date(now-(70-i)*86400000).toISOString().slice(0,10),open:100+i,high:102+i,low:99+i,close:101+i,adjusted_close:50+i/2,volume:10000}));}
test('directory declares exclusions, rejects duplicate identities and unsafe symbols',()=>{
  const rows=directory([record,{...record,Code:'ETF',Type:'ETF'},{...record,Code:'OTC',Exchange:'PINK'}],'US');
  assert.equal(rows[0].symbol,'ABC.US');assert.equal(rows[0].excluded,null);
  assert.equal(rows[1].excluded,'not_common_stock');assert.equal(rows[2].excluded,'venue_outside_scope');
  assert.throws(()=>directory([record,record],'US'),/duplicate/);
  assert.throws(()=>directory([{...record,Code:'../secret'}],'US'));
  assert.throws(()=>directory([], 'HK'));
});
test('trend observations use adjusted series, never imply buy/sell, reject stale or malformed bars',()=>{
  const rows=bars(), result=observePrices(rows,now);
  assert.equal(result.trend,'above_averages');assert.equal(result.entry,'insufficient');assert.equal(result.exit,'insufficient');
  assert.equal(result.lastClose,170);assert.ok(result.sma20Adjusted<100);
  assert.equal(observePrices(rows,now+9*86400000).status,'stale');
  assert.equal(observePrices(rows.slice(-20),now).status,'short_history');
  for(const bad of [[...rows,rows.at(-1)], [{...rows[0],date:'2026-02-30'}], [{...rows[0],adjusted_close:0}], [{...rows[0],volume:1.5}], [{...rows[0],low:200}]])assert.throws(()=>observePrices(bad,now));
});
test('coverage counts pending, excluded, failed and stale without market-wide claims',()=>{
  const rows=directory([record,{...record,Code:'OTHER'},{...record,Code:'FUND',Type:'ETF'},{...record,Code:'FAIL'}],'US');
  const state={directories:{US:{at:'2026-11-05',rows}},directoryErrors:{HK:'directory_unavailable'},observations:{'ABC.US':{attemptedAt:'2026-11-05',result:observePrices(bars(),now)},'FAIL.US':{attemptedAt:'2026-11-05',result:{status:'unavailable'}}}};
  const report=buildReport(state,now+9*86400000);
  assert.equal(report.fullMarketRecommendation,false);assert.deepEqual(report.rankedCandidates,[]);
  assert.deepEqual(report.markets[1].states,{stale:1,pending:1,excluded:1,unavailable:1});
  assert.equal(report.markets[2].providerListed,null);
  assert.equal(report.rows.length,4);
});
test('provider limits endpoints and hides authentication/network failures',async()=>{
  let called=false;
  await assert.rejects(providerJSON('https://evil.invalid','secret',async()=>{called=true;}),/invalid_endpoint/);assert.equal(called,false);
  await assert.rejects(providerJSON('eod/ABC.US','secret',async()=>{throw Error('https://api?api_token=secret');}),/^Error: network_unavailable$/);
  await assert.rejects(providerJSON('eod/ABC.US','secret',async()=>new Response('secret',{status:403})),/^Error: provider_403$/);
  const data=await providerJSON('exchange-symbol-list/US','secret',async(url,options)=>{
    assert.equal(url.origin,'https://eodhd.com');assert.equal(options.redirect,'error');assert.equal(url.searchParams.get('api_token'),'secret');
    return new Response(JSON.stringify([record]),{headers:{'Content-Type':'application/json'}});
  });assert.deepEqual(data,[record]);
});
