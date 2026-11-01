const reply = (status, body) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
async function readBytes(stream, max = 200_000) {
  if (!stream) throw new Error("empty");
  const reader = stream.getReader(), chunks = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > max) { await reader.cancel(); throw new Error("large"); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes;
}
const read = async (stream, max) => JSON.parse(new TextDecoder().decode(await readBytes(stream, max)));
const placeID = v => typeof v === "string" && /^[A-Za-z0-9_-]{1,256}$/.test(v);
export function validInput(v) {
  if (!v || !["search", "details"].includes(v.mode)) return false;
  if (v.mode === "details") return placeID(v.id);
  return typeof v.query === "string" && v.query.trim().length > 0 && v.query.length <= 300 &&
    ((v.latitude === undefined && v.longitude === undefined) ||
      (Number.isFinite(v.latitude) && Math.abs(v.latitude) <= 90 && Number.isFinite(v.longitude) && Math.abs(v.longitude) <= 180));
}
function safeURL(value, photo = false) {
  try {
    const u = new URL(value);
    const validHost = photo ? u.hostname.endsWith(".googleusercontent.com") :
      u.hostname === "google.com" || u.hostname.endsWith(".google.com") || u.hostname === "maps.app.goo.gl";
    return u.protocol === "https:" && !u.username && !u.password && !u.port && validHost ? u.href : "";
  } catch { return ""; }
}
function cleanPlace(p) {
  return { id: p.id, name: String(p.displayName?.text ?? ""), address: String(p.formattedAddress ?? ""),
    latitude: p.location?.latitude, longitude: p.location?.longitude,
    mapsURL: safeURL(p.googleMapsUri), attributions: (p.attributions ?? []).map(a => ({ name: String(a.provider ?? ""), url: safeURL(a.providerUri) })) };
}
export async function handlePlaces(request, deps) {
  if (request.method !== "POST") return reply(405, { error: "method" });
  const auth = request.headers.get("Authorization") ?? "";
  if (!/^Bearer \S+$/.test(auth)) return reply(401, { error: "sign_in_required" });
  const url = deps.env("SUPABASE_URL"), anon = deps.env("SUPABASE_ANON_KEY"), key = deps.env("GOOGLE_PLACES_API_KEY");
  if (!url || !anon || !key) return reply(503, { error: "not_configured" });
  const signal = AbortSignal.timeout(25_000);
  const get = (url, options = {}) => deps.fetch(url, { ...options, signal, redirect: "error" });
  const headers = { apikey: anon, Authorization: auth, "Content-Type": "application/json" };
  try {
    const userResponse = await get(url + "/auth/v1/user", { headers });
    if (!userResponse.ok) return reply(401, { error: "sign_in_required" });
    const user = await read(userResponse.body, 100_000);
    if (!user.id || user.is_anonymous === true) return reply(401, { error: "sign_in_required" });
    if (!request.headers.get("content-type")?.includes("application/json")) return reply(415, { error: "json_required" });
    let input;
    try { input = await read(request.body, 4_000); } catch { return reply(400, { error: "invalid_input" }); }
    if (!validInput(input)) return reply(400, { error: "invalid_input" });
    const quota = await get(url + "/rest/v1/rpc/claim_places_request", { method: "POST", headers, body: "{}" });
    if (!quota.ok) return reply(503, { error: "quota_unavailable" });
    if (await read(quota.body, 100) !== true) return reply(429, { error: "daily_limit" });
    const googleHeaders = { "Content-Type": "application/json", "X-Goog-Api-Key": key };
    const search = input.mode === "search";
    const mask = "id,displayName,formattedAddress,location,googleMapsUri,attributions";
    const body = { textQuery: input.query, pageSize: 5 };
    if (input.latitude !== undefined) body.locationBias = { circle: { center: { latitude: input.latitude, longitude: input.longitude }, radius: 500 } };
    const response = await get("https://places.googleapis.com/v1/" + (search ? "places:searchText" : "places/" + input.id), {
      method: search ? "POST" : "GET", headers: { ...googleHeaders,
        "X-Goog-FieldMask": search ? mask.split(",").map(f => "places." + f).join(",") : mask + ",photos" },
      ...(search ? { body: JSON.stringify(body) } : {}) });
    if (!response.ok) return reply(response.status === 429 ? 429 : 502, { error: response.status === 403 ? "places_access_denied" : "places_unavailable" });
    const result = await read(response.body);
    if (search) return reply(200, { places: (result.places ?? []).filter(p => placeID(p.id)).slice(0, 5).map(cleanPlace) });
    if (result.id !== input.id) return reply(502, { error: "places_unavailable" });
    const photos = [];
    // Fresh references only. No provider content is persisted and at most three photos are fetched per explicit selection.
    for (const p of (result.photos ?? []).slice(0, 3)) {
      if (typeof p.name !== "string" || !p.name.startsWith("places/" + input.id + "/photos/") || !/^places\/[A-Za-z0-9_-]+\/photos\/[A-Za-z0-9_-]+$/.test(p.name)) continue;
      const media = await get("https://places.googleapis.com/v1/" + p.name + "/media?maxWidthPx=900&skipHttpRedirect=true", { headers: googleHeaders });
      if (!media.ok) continue;
      const image = await read(media.body, 20_000), imageURL = safeURL(image.photoUri, true);
      if (!imageURL) continue;
      photos.push({ imageURL, mapsURL: safeURL(p.googleMapsUri) || safeURL(result.googleMapsUri),
        authors: (p.authorAttributions ?? []).map(a => ({ name: String(a.displayName ?? ""), url: safeURL(a.uri) })) });
    }
    let mapImage = null;
    const mapKey = deps.env("GOOGLE_MAPS_STATIC_API_KEY");
    if (photos.length === 0 && mapKey) {
      // Proxy a bounded image: the server key never reaches the app. Keep Google's
      // built-in map attribution visible; this is not an Apple map overlay.
      try {
        const params = new URLSearchParams({ center: "place_id:" + input.id, markers: "place_id:" + input.id,
          zoom: "16", size: "600x360", scale: "1", format: "png", key: mapKey });
        const map = await get("https://maps.googleapis.com/maps/api/staticmap?" + params);
        if (map.ok && map.headers.get("content-type")?.startsWith("image/png")) {
          const bytes = await readBytes(map.body, 1_500_000);
          let binary = "";
          for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
          mapImage = btoa(binary);
        }
      } catch { /* The place card still works when the optional map fails. */ }
    }
    return reply(200, { place: cleanPlace(result), photos, mapImage });
  } catch { return reply(502, { error: signal.aborted ? "places_timeout" : "places_unavailable" }); }
}
