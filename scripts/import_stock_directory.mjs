// Build-time public identity/logo import. Never imports quotes or AI evidence.
// Run explicitly; no network requests occur when displaying bundled stock logos.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const assets = path.join(root, 'YueJi/Assets.xcassets');
const swift = await readFile(path.join(root, 'YueJi/InvestmentViews.swift'), 'utf8');
const symbols = [...swift.matchAll(/\.init\(symbol: "([^"]+)", name:/g)].map(m => m[1]);
const records = {}, errors = [];
if (process.argv.includes('--resume')) {
  const prior = JSON.parse(await readFile(path.join(assets,'StockDirectory.dataset/directory.json'),'utf8'));
  for (const symbol of symbols) if (prior[symbol]) records[symbol] = prior[symbol];
}
const decode = s => s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
async function get(url) {
  const r = await fetch(url, { signal: AbortSignal.timeout(25000) });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r;
}
async function collect(symbol) {
  const slug = symbol.replace(':', '-');
  const url = `https://www.tradingview.com/symbols/${slug}/`;
  const response = await get(url), html = await response.text();
  const title = decode(html.match(/<meta property="og:title" content="([^"]+)"/)?.[1] ?? '');
  // A generic/redirected page must not supply another company's identity or logo.
  const identity = html.match(/"data":\{"symbol":\{"pro_symbol":"([^"]+)"/)?.[1];
  if (identity !== symbol) throw new Error(`identity mismatch: ${identity ?? title}`);
  const logo = html.match(/<meta property="og:image" content="(https:\/\/s3-symbol-logo\.tradingview\.com\/[a-zA-Z0-9/_-]+--600\.png)"/)?.[1];
  if (!logo) throw new Error('no company PNG');
  const imageResponse = await get(logo), image = Buffer.from(await imageResponse.arrayBuffer());
  if (image.length > 2000000 || !image.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw new Error('invalid image');
  const asset = `StockLogo_${slug}`;
  const folder = path.join(assets, `${asset}.imageset`);
  await mkdir(folder, {recursive:true});
  await writeFile(path.join(folder, 'logo.png'), image);
  await writeFile(path.join(folder, 'Contents.json'), JSON.stringify({images:[{filename:'logo.png',idiom:'universal'}],info:{author:'xcode',version:1}},null,2)+'\n');
  const crumbs = [...html.matchAll(/<script[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/g)].flatMap(m=>{try{return JSON.parse(m[1]).itemListElement ?? [];}catch{return [];}});
  const sector = crumbs.find(c=>c.item?.['@id']?.includes('/sectorandindustry-sector/'))?.item?.name ?? '';
  const industry = crumbs.find(c=>c.item?.['@id']?.includes('/sectorandindustry-industry/'))?.item?.name ?? '';
  const websiteMatch = [...html.matchAll(/<a\b[^>]*data-overflow-tooltip-text="([^"]+)"[^>]*href="(https?:\/\/[^\"]+)"/g)].find(m=>{try{return new URL(decode(m[2])).hostname.replace(/^www\./,'') === m[1].replace(/^www\./,'');}catch{return false;}});
  const website = websiteMatch ? decode(websiteMatch[2]) : null;
  records[symbol] = {symbol,logoAsset:asset,profileURL:url,website,sector,industry,logoSource:logo,checkedAt:new Date().toISOString().slice(0,10)};
  console.log(`OK ${symbol}`);
}
let next = 0;
await Promise.all(Array.from({length:3},async()=>{while(next<symbols.length){const symbol=symbols[next++];if(records[symbol])continue;try{await collect(symbol);}catch(e){errors.push({symbol,error:e.message});console.log(`FAIL ${symbol}: ${e.message}`);}}}));
const folder = path.join(assets,'StockDirectory.dataset');
await mkdir(folder,{recursive:true});
await writeFile(path.join(folder,'directory.json'),JSON.stringify(Object.fromEntries(Object.entries(records).sort(([a],[b])=>a.localeCompare(b))),null,2)+'\n');
await writeFile(path.join(folder,'Contents.json'),JSON.stringify({data:[{filename:'directory.json',idiom:'universal'}],info:{author:'xcode',version:1}},null,2)+'\n');
console.log(JSON.stringify({covered:Object.keys(records).length,total:symbols.length,errors}));
if(errors.length)process.exitCode=1;
