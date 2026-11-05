// Local, resumable free-plan ingestion. Never run inside the 25-second Edge Function.
import {mkdir,readFile,writeFile,rename,open,unlink} from 'node:fs/promises';
import path from 'node:path';
import {markets,directory,observePrices,providerJSON,buildReport} from './lib/free-market-scan.mjs';
const root=path.resolve(import.meta.dirname,'../build-market-scan');
const key=process.env.EODHD_API_KEY;
if (!key || key==='demo') { console.error('Set EODHD_API_KEY locally to your own free-account key. No request was made. Never paste the key into chat.'); process.exit(2); }
await mkdir(root,{recursive:true});
let lock;
try {lock=await open(path.join(root,'run.lock'),'wx');} catch {console.error('Another scan may be running. No requests made.');process.exit(2);}
const atomic=async(name,value)=>{const dest=path.join(root,name);await writeFile(dest+'.tmp',JSON.stringify(value,null,2));await rename(dest+'.tmp',dest);};
try {
  let state;
  try {state=JSON.parse(await readFile(path.join(root,'state.json'),'utf8'));}
  catch(e){if(e.code!=='ENOENT')throw Error('invalid_state');state={version:1,usage:{},directories:{},directoryErrors:{},observations:{}};}
  if(state.version!==1 || !state.usage || !state.directories || !state.observations || !state.directoryErrors)throw Error('invalid_state');
  let stop=false,usedThisRun=0;
  const utcDay=new Date().toISOString().slice(0,10);
  if (!Number.isInteger(state.usage[utcDay]??0) || (state.usage[utcDay]??0)<0)throw Error('invalid_usage');
  async function get(endpoint){
    if(stop || (state.usage[utcDay]??0)>=20)throw Error('local_daily_limit');
    state.usage[utcDay]=(state.usage[utcDay]??0)+1;usedThisRun++;
    await atomic('state.json',state); // Reserve before network; failed requests still count.
    if(usedThisRun>1)await new Promise(resolve=>setTimeout(resolve,3200));
    try{return await providerJSON(endpoint,key);}catch(e){if(/^provider_(401|403|429)$/.test(e.message))stop=true;throw e;}
  }
  for(const market of markets){
    const prior=state.directories[market];
    if(prior && Date.now()-Date.parse(prior.at)<7*86400000)continue;
    if(stop || (state.usage[utcDay]??0)>=20)break;
    try {const rows=directory(await get(`exchange-symbol-list/${market}`),market);state.directories[market]={at:new Date().toISOString(),rows};delete state.directoryErrors[market];}
    catch(e){state.directoryErrors[market]=['local_daily_limit','provider_401','provider_403','provider_429','invalid_directory','duplicate_symbol'].includes(e.message)?e.message:'directory_unavailable';}
    await atomic('state.json',state);
  }
  // Oldest attempts first within each market, round-robin across markets.
  // Repeated failures do not permanently starve later symbols.
  const queues=markets.map(m=>(state.directories[m]?.rows??[]).filter(s=>!s.excluded &&
    (!state.observations[s.symbol] || Date.now()-Date.parse(state.observations[s.symbol].attemptedAt)>86400000))
    .sort((a,b)=>(Date.parse(state.observations[a.symbol]?.attemptedAt??'1970-01-01')-Date.parse(state.observations[b.symbol]?.attemptedAt??'1970-01-01')) || a.symbol.localeCompare(b.symbol)));
  while(!stop && (state.usage[utcDay]??0)<20 && queues.some(q=>q.length)){
    for(const queue of queues){
      if(stop || (state.usage[utcDay]??0)>=20)break;
      const stock=queue.shift();if(!stock)continue;
      let result;
      try{result=observePrices(await get(`eod/${stock.symbol}`));}
      catch(e){result={status:'unavailable',reason:['provider_401','provider_403','provider_429','invalid_prices'].includes(e.message)?e.message:'prices_unavailable'};}
      state.observations[stock.symbol]={attemptedAt:new Date().toISOString(),result};await atomic('state.json',state);
    }
  }
  await atomic('report.json',buildReport(state));
  console.log(`Saved build-market-scan/report.json. Requests this run: ${usedThisRun}; locally recorded today: ${state.usage[utcDay]??0}/20. No buy/sell recommendation.`);
}catch{console.error('Scan stopped safely. Check local state and permissions. No API key or upstream response is logged.');process.exitCode=1;}
finally{await lock.close();await unlink(path.join(root,'run.lock'));}
