import "dotenv/config";
import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { runBot } from "./index.js";

const port = Number(process.env.PORT ?? 3000);
const password = required("MOBILE_APP_PASSWORD");
const tokenSecret = required("MOBILE_TOKEN_SECRET");
let isRunning = false;
let lastRunAt = 0;

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function json(response: ServerResponse, status: number, body: unknown) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  response.end(JSON.stringify(body));
}

function sign(payload: string): string {
  return createHmac("sha256", tokenSecret).update(payload).digest("base64url");
}

function issueToken(): string {
  const payload = Buffer.from(JSON.stringify({ exp: Date.now() + 30 * 24 * 60 * 60 * 1000, nonce: randomBytes(12).toString("hex") })).toString("base64url");
  return `${payload}.${sign(payload)}`;
}

function authorized(request: IncomingMessage): boolean {
  const token = request.headers.authorization?.replace(/^Bearer\s+/i, "");
  if (!token) return false;
  const [payload, signature] = token.split(".");
  if (!payload || !signature) return false;
  const expected = sign(payload);
  if (signature.length !== expected.length || !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return false;
  try {
    return JSON.parse(Buffer.from(payload, "base64url").toString()).exp > Date.now();
  } catch {
    return false;
  }
}

async function readJson(request: IncomingMessage): Promise<Record<string, unknown>> {
  let text = "";
  for await (const chunk of request) {
    text += chunk;
    if (text.length > 16_384) throw new Error("Request body is too large");
  }
  return JSON.parse(text || "{}");
}

function sameSecret(left: string, right: string): boolean {
  const leftHash = createHmac("sha256", "password-compare").update(left).digest();
  const rightHash = createHmac("sha256", "password-compare").update(right).digest();
  return timingSafeEqual(leftHash, rightHash);
}

createServer(async (request, response) => {
  if (request.method === "GET" && request.url === "/health") {
    json(response, 200, { ok: true });
    return;
  }

  if (request.method === "POST" && request.url === "/v1/auth/login") {
    try {
      const body = await readJson(request);
      if (typeof body.password !== "string" || !sameSecret(body.password, password)) {
        json(response, 401, { error: "Invalid password" });
        return;
      }
      json(response, 200, { token: issueToken() });
    } catch {
      json(response, 400, { error: "Invalid request" });
    }
    return;
  }

  if (request.method === "POST" && request.url === "/v1/bot/run") {
    if (!authorized(request)) {
      json(response, 401, { error: "Sign in again to continue" });
      return;
    }
    if (isRunning) {
      json(response, 409, { error: "A run is already in progress" });
      return;
    }
    if (Date.now() - lastRunAt < 30_000) {
      json(response, 429, { error: "Please wait 30 seconds before another run" });
      return;
    }
    isRunning = true;
    lastRunAt = Date.now();
    try {
      const result = await runBot(() => undefined);
      json(response, 200, result);
    } catch (error) {
      console.error(error);
      json(response, 500, { error: "The server could not complete the run" });
    } finally {
      isRunning = false;
    }
    return;
  }

  json(response, 404, { error: "Not found" });
}).listen(port, "0.0.0.0", () => {
  console.log(`Mobile API listening on port ${port}`);
});
