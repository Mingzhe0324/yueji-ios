import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const assets=path.join(root,'YueJi/Assets.xcassets');
const swift=await readFile(path.join(root,'YueJi/InvestmentViews.swift'),'utf8');
const symbols=[...swift.matchAll(/\.init\(symbol: "([^"]+)", name:/g)].map(m=>m[1]);
const records=JSON.parse(await readFile(path.join(assets,'StockDirectory.dataset/directory.json'),'utf8'));
assert.deepEqual(Object.keys(records).sort(),symbols.sort());
let bytes=0;
for(const symbol of symbols){
 const r=records[symbol];
 assert.equal(r.symbol,symbol);
 assert.equal(r.profileURL,`https://www.tradingview.com/symbols/${symbol.replace(':','-')}/`);
 assert.ok(r.website && r.sector && r.industry && /^\d{4}-\d{2}-\d{2}$/.test(r.checkedAt),symbol);
 assert.ok(['http:','https:'].includes(new URL(r.website).protocol));
 assert.equal(new URL(r.logoSource).hostname,'s3-symbol-logo.tradingview.com');
 const folder=path.join(assets,`${r.logoAsset}.imageset`);
 const manifest=JSON.parse(await readFile(path.join(folder,'Contents.json'),'utf8'));
 const png=await readFile(path.join(folder,manifest.images[0].filename));
 assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a',symbol);
 assert.ok(png.readUInt32BE(16)>0 && png.readUInt32BE(20)>0,symbol);
 bytes+=png.length;
}
console.log(`PASS: ${symbols.length}/${symbols.length} stocks have identity, website, industry, source and bundled PNG (${bytes} bytes).`);
