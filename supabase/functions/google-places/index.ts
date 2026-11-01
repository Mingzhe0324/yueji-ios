import { handlePlaces } from "./handler.mjs";
Deno.serve((request: Request) => handlePlaces(request, { env: (name: string) => Deno.env.get(name), fetch }));
