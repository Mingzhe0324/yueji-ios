import { handleBankNotification } from "./handler.mjs";

Deno.serve((request: Request) => handleBankNotification(request, { env: (name: string) => Deno.env.get(name), fetch }));
