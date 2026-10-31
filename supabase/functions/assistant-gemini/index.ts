import { handleAssistant } from "./handler.mjs";
Deno.serve((request: Request) => handleAssistant(request, { env: (name: string) => Deno.env.get(name), fetch }));
