import test from 'node:test';
import assert from 'node:assert/strict';
import { handlePlaces, validInput } from '../../supabase/functions/google-places/handler.mjs';
const json = (data, status = 200) => new Response(JSON.stringify(data), { status });
const request = (body, auth = 'Bearer token') => new Request('https://local', {method:'POST',headers:{Authorization:auth,'Content-Type':'application/json'},body:JSON.stringify(body)});
function setup(responses) {
  const calls=[];
  return {calls, env: name => ({SUPABASE_URL:'https://project',SUPABASE_ANON_KEY:'anon',GOOGLE_PLACES_API_KEY:'private-secret'})[name],
    fetch: async (url, options) => { calls.push({url,options}); assert.ok(responses.length); return responses.shift(); }};
}
test('rejects invalid coordinates, IDs and empty searches', () => {
  for (const v of [{mode:'search',query:''},{mode:'search',query:'cafe',latitude:1},{mode:'search',query:'cafe',latitude:91,longitude:1},{mode:'details',id:'../secret'}]) assert.equal(validInput(v),false);
  assert.equal(validInput({mode:'search',query:'cafe',latitude:0,longitude:0}),true);
});
test('no authentication never calls Google', async () => {
  const deps=setup([]); assert.equal((await handlePlaces(request({mode:'search',query:'cafe'},''),deps)).status,401); assert.equal(deps.calls.length,0);
});
test('anonymous and quota exhausted never call Google', async () => {
  for(const anonymous of [true,false]) {
    const deps=setup([json({id:'u',is_anonymous:anonymous}),json(false)]);
    const result=await handlePlaces(request({mode:'search',query:'cafe'}),deps);
    assert.equal(result.status,anonymous?401:429); assert.equal(deps.calls.some(c=>c.url.includes('googleapis')),false);
  }
});
test('search uses bounded field masks, preserves attributions and keeps secrets server-side',async()=>{
  const deps=setup([json({id:'u'}),json(true),json({places:[{id:'abc',displayName:{text:'Cafe'},formattedAddress:'Street',googleMapsUri:'https://maps.google.com/place',attributions:[{provider:'Provider',providerUri:'https://maps.google.com/source'}]}]})]);
  const response=await handlePlaces(request({mode:'search',query:'Cafe',latitude:1,longitude:2}),deps);
  const body=await response.json(); assert.equal(body.places[0].name,'Cafe'); assert.equal(body.places[0].attributions[0].name,'Provider');
  const call=deps.calls[2]; assert.equal(JSON.parse(call.options.body).pageSize,5); assert.equal(JSON.parse(call.options.body).locationBias.circle.center.longitude,2);
  assert.ok(!call.options.headers['X-Goog-FieldMask'].includes('*')); assert.equal(response.headers.get('Cache-Control'),'no-store'); assert.ok(!JSON.stringify(body).includes('private-secret'));
});
test('details load fresh photos, preserve author credit, never accept arbitrary image hosts',async()=>{
  const deps=setup([json({id:'u'}),json(true),json({id:'abc',displayName:{text:'Cafe'},photos:[{name:'places/abc/photos/ref',googleMapsUri:'https://maps.google.com/photo',authorAttributions:[{displayName:'Photographer',uri:'https://maps.google.com/author'}]},{name:'places/abc/photos/other'}]}),json({photoUri:'https://lh3.googleusercontent.com/image'}),json({photoUri:'https://evil.example/image'})]);
  const response=await handlePlaces(request({mode:'details',id:'abc'}),deps); const body=await response.json();
  assert.equal(body.photos.length,1); assert.equal(body.photos[0].authors[0].name,'Photographer'); assert.equal(deps.calls[3].options.redirect,'error');
});
test('upstream failures sanitize errors',async()=>{
  const deps=setup([json({id:'u'}),json(true),json({error:'private-secret'},403)]);
  const response=await handlePlaces(request({mode:'search',query:'Cafe'}),deps); assert.equal(response.status,502); assert.deepEqual(await response.json(),{error:'places_access_denied'});
});
test('oversized input rejected before quota and provider calls',async()=>{
  const deps=setup([json({id:'u'})]); const response=await handlePlaces(request({mode:'search',query:'x'.repeat(5000)}),deps);
  assert.equal(response.status,400); assert.equal(deps.calls.length,1);
});
test('details with no photos succeeds without media calls',async()=>{
  const deps=setup([json({id:'u'}),json(true),json({id:'abc',displayName:{text:'Cafe'}})]);
  const response=await handlePlaces(request({mode:'details',id:'abc'}),deps); assert.deepEqual((await response.json()).photos,[]); assert.equal(deps.calls.length,3);
});
test('missing photos fall back to a bounded Google map without exposing the key',async()=>{
  const deps=setup([json({id:'u'}),json(true),json({id:'abc',displayName:{text:'Cafe'},location:{latitude:1,longitude:2}}),new Response(new Uint8Array([137,80,78,71]),{headers:{'Content-Type':'image/png'}})]);
  const env=deps.env; deps.env=name=>name==='GOOGLE_MAPS_STATIC_API_KEY'?'map-secret':env(name);
  const response=await handlePlaces(request({mode:'details',id:'abc'}),deps); const body=await response.json();
  assert.equal(body.mapImage,'iVBORw=='); assert.equal(body.place.latitude,1); assert.ok(!JSON.stringify(body).includes('map-secret'));
  assert.equal(new URL(deps.calls[3].url).searchParams.get('center'),'place_id:abc');
});
test('map provider failure preserves place details',async()=>{
  const deps=setup([json({id:'u'}),json(true),json({id:'abc',displayName:{text:'Cafe'}}),json({error:'map-secret'},403)]);
  const env=deps.env; deps.env=name=>name==='GOOGLE_MAPS_STATIC_API_KEY'?'map-secret':env(name);
  const response=await handlePlaces(request({mode:'details',id:'abc'}),deps); const body=await response.json();
  assert.equal(response.status,200); assert.equal(body.mapImage,null); assert.equal(body.place.name,'Cafe');
});
