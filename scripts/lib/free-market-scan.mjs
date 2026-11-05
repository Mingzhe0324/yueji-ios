// EODHD personal/free adapter. No keys, URLs, or model text are persisted.
export const markets = ['KLSE', 'US', 'HK'];
const day = 86400000;
const validDate = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0,10) === value;
export function directory(rows, market) {
  if (!markets.includes(market) || !Array.isArray(rows) || !rows.length || rows.length > 100000) throw Error('invalid_directory');
  const counts = new Map();
  for (const r of rows) if (typeof r?.Code === 'string') counts.set(r.Code, (counts.get(r.Code)??0)+1);
  return rows.map((r,index) => {
    // Mixed-instrument directories can contain incomplete or unsupported records.
    // Preserve each as an excluded row instead of dropping an entire exchange.
    const validCode = typeof r?.Code === 'string' && /^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/.test(r.Code);
    if (!r || !validCode ||
        typeof r.Name !== 'string' || !r.Name.trim() || r.Name.length > 300 ||
        typeof r.Type !== 'string' || typeof r.Exchange !== 'string' ||
        typeof r.Currency !== 'string' || !/^[A-Z]{3}$/.test(r.Currency) || counts.get(r.Code)>1) {
      return {symbol:`INVALID-${market}-${index}`,market,name:'Unusable provider directory record',currency:null,venue:null,type:null,
        excluded:validCode && counts.get(r.Code)>1?'duplicate_identity':'invalid_metadata',providerCode:typeof r?.Code==='string'?r.Code.slice(0,80):null};
    }
    const symbol = `${r.Code}.${market}`;
    // US means this explicitly declared venue set, never all US OTC securities.
    const excluded = r.Type !== 'Common Stock' ? 'not_common_stock' : market === 'US' && !['NYSE','NASDAQ','NYSE ARCA','BATS','NYSE MKT','AMEX'].includes(r.Exchange) ? 'venue_outside_scope' : null;
    return {symbol,market,name:r.Name,currency:r.Currency,venue:r.Exchange,type:r.Type,excluded};
  });
}
export function observePrices(rows, now = Date.now()) {
  if (!Array.isArray(rows) || !rows.length || rows.length > 400) throw Error('invalid_prices');
  let previous = '';
  for (const r of rows) {
    if (!r || !validDate(r.date) || r.date <= previous || Date.parse(r.date) > now ||
        !['open','high','low','close','adjusted_close','volume'].every(k=>typeof r[k]==='number' && Number.isFinite(r[k])) ||
        r.low <= 0 || r.adjusted_close <= 0 || r.high > 1e12 || r.adjusted_close > 1e12 || r.high < Math.max(r.open,r.close) || r.low > Math.min(r.open,r.close) ||
        !Number.isSafeInteger(r.volume) || r.volume < 0) throw Error('invalid_prices');
    previous = r.date;
  }
  const last=rows.at(-1), stale=now-Date.parse(last.date)>7*day;
  if (stale || rows.length < 60) return {status:stale?'stale':'short_history',through:last.date,count:rows.length};
  const mean=n=>rows.slice(-n).reduce((s,r)=>s+r.adjusted_close,0)/n;
  const sma20=mean(20), sma60=mean(60);
  // Adjusted series is for relative trends, NEVER an executable order price.
  const trend=last.adjusted_close>sma20 && sma20>sma60?'above_averages':last.adjusted_close<sma20 && sma20<sma60?'below_averages':'mixed';
  return {status:'observed',through:last.date,count:rows.length,lastClose:last.close,sma20Adjusted:sma20,sma60Adjusted:sma60,
    trend,volume:last.volume,entry:'insufficient',exit:'insufficient',missing:['fundamentals','valuation','announcements','trading_status','user_circumstances'],
    conditions:{entry:'Verify dated financials, comparable valuation, liquidity and event risks before considering any purchase. A moving-average observation is not an entry signal.',
      exit:'For an existing holding, reassess if the business thesis or your cash needs change. Below-average prices alone do not establish a sell instruction.'}};
}
export async function providerJSON(endpoint, key, fetcher=fetch) {
  if (!/^(exchange-symbol-list\/(KLSE|US|HK)|eod\/[A-Za-z0-9][A-Za-z0-9._-]{0,39}\.(KLSE|US|HK))$/.test(endpoint)) throw Error('invalid_endpoint');
  const url=new URL(`https://eodhd.com/api/${endpoint}`);
  url.searchParams.set('api_token',key); url.searchParams.set('fmt','json');
  if(endpoint.startsWith('eod/')) {
    url.searchParams.set('period','d'); url.searchParams.set('order','a');
    url.searchParams.set('from',new Date(Date.now()-364*day).toISOString().slice(0,10));
  }
  let response;
  try { response=await fetcher(url,{redirect:'error',signal:AbortSignal.timeout(20000)}); } catch { throw Error('network_unavailable'); }
  if (!response.ok) { await response.body?.cancel(); throw Error([401,403,429].includes(response.status)?`provider_${response.status}`:'provider_unavailable'); }
  if (!response.body || !response.headers.get('content-type')?.includes('json')) { await response.body?.cancel(); throw Error('invalid_response'); }
  const reader=response.body.getReader(), chunks=[]; let size=0;
  try {
    while(true) { const {done,value}=await reader.read(); if(done)break; size+=value.length;
      if(size>20000000){await reader.cancel();throw Error('response_too_large');} chunks.push(value); }
  } finally {reader.releaseLock();}
  const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
  try{return JSON.parse(new TextDecoder().decode(bytes));}catch{throw Error('invalid_response');}
}
export function buildReport(state, now=Date.now()) {
  const rows=markets.flatMap(m=>(state.directories[m]?.rows??[]).map(stock=>{
    const attempt=state.observations[stock.symbol];
    if(stock.excluded)return {...stock,status:'excluded',reason:stock.excluded};
    if(!attempt)return {...stock,status:'pending'};
    // Recompute freshness on every run, including runs with exhausted quota.
    const stale=attempt.result?.through && now-Date.parse(attempt.result.through)>7*day;
    return {...stock,...attempt.result,status:stale?'stale':attempt.result.status,attemptedAt:attempt.attemptedAt};
  }));
  return {version:1,generatedAt:new Date(now).toISOString(),provider:'EODHD',scope:'Provider KLSE/HK common stocks; US common stocks on declared exchange venues; no OTC, ETF, warrants or deduplication of dual listings',
    fullMarketRecommendation:false,recommendation:'insufficient',rankedCandidates:[],
    notes:['No fundamental data in this free adapter. No AI decisions, live quotes, backtest or trade execution.',
      'Freshness uses a seven-calendar-day ceiling, not an exchange trading calendar. Recent bars can still be incomplete.',
      'Directory snapshots are provider coverage, not reconciled official exchange totals. Rows are not ranked.'],
    markets:markets.map(m=>({market:m,directoryAt:state.directories[m]?.at??null,directoryError:state.directoryErrors[m]??null,
      providerListed:state.directories[m]?.rows.length??null,states:rows.filter(r=>r.market===m).reduce((counts,r)=>({...counts,[r.status]:(counts[r.status]??0)+1}),{})})),rows};
}
