// Manufacturer model reference images, not exact year/trim/paint matches.
import {mkdir,writeFile} from 'node:fs/promises';
const perodua = {
 Axia:'new_axia/our_car_models/Axia-category-image-ssilver-01.webp',
 Alza:'new_alza/cp-assets/EN/our_models/Thumbnail.webp',
 Myvi:'myvi-category-image.webp', Ativa:'choosecar-ativa-cblue.webp',
 Aruz:'aruz/choosecar-aruzpi-brown.webp', Bezza:'choosecar-bezza.webp'
};
const proton = {X50:'wxaip352/model-x50-01-copy.png',X70:'e3jm4grp/model-x70.png',
 X90:'xcxpvkh5/model-x90.png',S70:'pwtfsjvq/model-s70.png',Saga:'yileabdk/model-saga_360x200.png'};
const rows = [
 ...Object.entries(perodua).map(([model,path])=>({brand:'Perodua',model,url:`https://www.perodua.com.my/img.php?a=images/${path}&w=960&v=2`,page:'https://www.perodua.com.my/our-models/choose-model'})),
 ...Object.entries(proton).map(([model,path])=>({brand:'Proton',model,url:`https://cms-assets.proton.com/proton-cms-blob/media/${path}`,page:'https://www.proton.com/'}))
];
await mkdir('../builds/vehicle-images',{recursive:true});
for (const row of rows) {
 const response=await fetch(row.url,{signal:AbortSignal.timeout(30000)});
 if(!response.ok || !response.headers.get('content-type')?.startsWith('image/'))throw Error(`Image unavailable: ${row.model}`);
 row.asset=`Vehicle_${row.brand}_${row.model}`;
 await writeFile(`../builds/vehicle-images/${row.asset}.image`,new Uint8Array(await response.arrayBuffer()));
}
await writeFile('docs/vehicle-image-sources.json',JSON.stringify({note:'Manufacturer reference imagery. Copyright belongs to the respective manufacturers. Does not assert exact year, trim or paint match.',images:rows},null,2)+'\n');
console.log(`Downloaded ${rows.length} model reference images for PNG conversion.`);
