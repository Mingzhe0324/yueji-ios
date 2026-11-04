import { handleResearch } from "./handler.mjs";
Deno.serve((request: Request) => handleResearch(request, { env: (name: string) => Deno.env.get(name), fetch }));
