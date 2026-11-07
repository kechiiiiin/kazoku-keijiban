// テストの下まわり: D1（node:sqlite）・関所のモック・waitUntil を受ける ctx・APNs の送り口のモック
import { createApp, type AppDeps } from "../src/app.ts";
import type { Env } from "../src/env.ts";
import type { Sekisho } from "../src/auth.ts";
import type { ApnsResult, ApnsSender } from "../src/apns.ts";
import { makeDb } from "./d1shim.ts";

export const AUD = "test-aud";
export const CLIENT_ID = "abc123def456.access";
export const MEMBERS = "A,B,C,D";

/** 関所のふり: "ok.jwt" = 許可された Client ID、"other.jwt" = 許可外の Client ID、"user.jwt" = ブラウザのユーザー */
export function mockSekisho(): Sekisho {
  return {
    async verify(token, aud, opts) {
      if (aud !== AUD || opts?.allowServiceTokens !== true) return null;
      if (token === "ok.jwt") return { kind: "service", clientId: CLIENT_ID.toUpperCase() };
      if (token === "other.jwt") return { kind: "service", clientId: "9999.access" };
      if (token === "user.jwt") return { kind: "user", email: "someone@example.com" };
      return null;
    },
  };
}

export class Clock {
  t: number;
  constructor(iso: string) {
    this.t = Date.parse(iso);
  }
  now = () => new Date(this.t);
  set(iso: string) {
    this.t = Date.parse(iso);
  }
}

export class MockSender implements ApnsSender {
  sent: string[] = [];
  replies: Record<string, ApnsResult> = {};
  async send(token: string): Promise<ApnsResult> {
    this.sent.push(token);
    return this.replies[token] ?? { status: 200 };
  }
}

export function setup(o: { now?: string; env?: Partial<Env>; deps?: Partial<AppDeps> } = {}) {
  const { db, raw } = makeDb();
  const clock = new Clock(o.now ?? "2026-11-07T03:00:00Z"); // 11/7 12:00 JST
  const sender = new MockSender();
  const waits: Promise<unknown>[] = [];
  const env = {
    DB: db,
    SEKISHO: mockSekisho(),
    CF_ACCESS_AUD: AUD,
    ACCESS_SERVICE_CLIENT_IDS: CLIENT_ID,
    MEMBERS,
    ...o.env,
  } as Env;
  const app = createApp({ now: clock.now, sender: () => sender, debounceMs: 0, sleep: async () => {}, ...o.deps });
  const ctx = {
    waitUntil: (p: Promise<unknown>) => void waits.push(p),
    passThroughOnException() {},
    props: {},
  } as unknown as ExecutionContext;

  async function call(method: string, path: string, body?: unknown, token: string | null = "ok.jwt") {
    const headers: Record<string, string> = {};
    if (token) headers["Cf-Access-Jwt-Assertion"] = token;
    if (body !== undefined) headers["Content-Type"] = "application/json";
    const res = await app.request(
      `https://kazoku.example.com${path}`,
      { method, headers, body: body === undefined ? undefined : JSON.stringify(body) },
      env,
      ctx,
    );
    const json = (await res.json()) as any;
    return { status: res.status, json };
  }
  /** waitUntil に積まれたもの（プッシュ）を全部待つ */
  async function settle() {
    while (waits.length) await waits.shift();
  }
  return { db, raw, clock, sender, env, call, settle, waits };
}
