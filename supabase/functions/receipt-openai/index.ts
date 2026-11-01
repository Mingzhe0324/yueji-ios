import { handleReceipt } from "./handler.mjs";

Deno.serve((request: Request) => handleReceipt(request, { env: (name: string) => Deno.env.get(name), fetch }));
