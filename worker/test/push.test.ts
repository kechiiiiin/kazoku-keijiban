// 受け入れ条件4: 変更系のあと、登録済みトークンへウィジェット用プッシュを送る（APNs はモック）。間引きも
import { test } from "node:test";
import assert from "node:assert/strict";
import { setup, MockSender } from "./helpers.ts";
import { notifyChange } from "../src/push.ts";
import {
  apnsConfig,
  httpApnsSender,
  makeProviderToken,
  importP8,
  resetTokenCacheForTest,
  widgetTopic,
  WIDGET_PAYLOAD,
} from "../src/apns.ts";
import type { Env } from "../src/env.ts";

const T1 = "aa".repeat(32);
const T2 = "bb".repeat(32);

async function withDevices() {
  const s = setup();
  await s.call("PUT", "/api/devices", { push_token: T1, member: "A" });
  await s.call("PUT", "/api/devices", { push_token: T2, member: "B" });
  await s.settle();
  return s;
}

test("変更系（足す・○⇄✓・外す・戻り時刻）のあと、登録済みの全トークンへ送る", async () => {
  const s = await withDevices();
  assert.deepEqual(s.sender.sent, []); // 端末の登録では送らない
  const id = (await s.call("POST", "/api/items", { kind: "daily", title: "風呂掃除", by: "A" })).json.daily[0].id;
  await s.settle();
  assert.deepEqual(s.sender.sent.sort(), [T1, T2]);
  for (const [m, p, b] of [
    ["POST", `/api/items/${id}/toggle`, { by: "A" }],
    ["PUT", "/api/settings/reset-time", { reset_time: "05:00" }],
    ["DELETE", `/api/items/${id}`, undefined],
  ] as const) {
    s.sender.sent = [];
    await s.call(m, p, b);
    await s.settle();
    assert.deepEqual(s.sender.sent.sort(), [T1, T2], `${m} ${p}`);
  }
});

test("読むだけ・失敗した変更では送らない", async () => {
  const s = await withDevices();
  await s.call("GET", "/api/board");
  await s.call("POST", "/api/items", { kind: "need", title: "", by: "A" });
  await s.call("POST", "/api/items/999/toggle", { by: "A" });
  await s.settle();
  assert.deepEqual(s.sender.sent, []);
});

test("間引き: 待ち時間の内に続いた変更は、最後の1回だけが送る", async () => {
  // 眠りを手で解く sleep。3回の変更が全部眠っている間に起こす
  const gates: (() => void)[] = [];
  const s = setup({ deps: { sleep: () => new Promise<void>((r) => gates.push(r)) } });
  await s.call("PUT", "/api/devices", { push_token: T1, member: "A" });
  await s.call("POST", "/api/items", { kind: "need", title: "玉ねぎ", by: "A" });
  await s.call("POST", "/api/items", { kind: "need", title: "牛乳", by: "A" });
  await s.call("POST", "/api/items", { kind: "need", title: "卵", by: "A" });
  // waitUntil の中で seq を取って眠りに入るまで待つ
  while (gates.length < 3) await new Promise((r) => setImmediate(r));
  gates.forEach((g) => g());
  await s.settle();
  assert.deepEqual(s.sender.sent, [T1]);
  const st = s.raw.prepare("SELECT seq, sent_seq FROM push_state").get() as { seq: number; sent_seq: number };
  assert.deepEqual({ ...st }, { seq: 3, sent_seq: 3 });
});

test("間引き: 静かになってからの変更はまた送る", async () => {
  const s = await withDevices();
  await s.call("POST", "/api/items", { kind: "need", title: "玉ねぎ", by: "A" });
  await s.settle();
  await s.call("POST", "/api/items", { kind: "need", title: "牛乳", by: "A" });
  await s.settle();
  assert.equal(s.sender.sent.length, 4);
});

test("notifyChange: 後から来た変更があれば自分は送らない（superseded）", async () => {
  const s = setup();
  const sender = new MockSender();
  let resolveFirst!: () => void;
  const first = notifyChange(s.db, { sender, sleep: () => new Promise<void>((r) => (resolveFirst = r)) });
  while (!resolveFirst) await new Promise((r) => setImmediate(r));
  const second = await notifyChange(s.db, { sender, sleep: async () => {} });
  resolveFirst();
  assert.deepEqual(await first, { sent: 0, skipped: "superseded" });
  assert.deepEqual(second, { sent: 0, skipped: null }); // 端末が無いので0通
});

test("APNs の鍵が無ければ送らない（一覧の読み書きは動く）", async () => {
  const s = setup({ deps: { sender: () => null } });
  await s.call("PUT", "/api/devices", { push_token: T1, member: "A" });
  assert.equal((await s.call("POST", "/api/items", { kind: "need", title: "玉ねぎ", by: "A" })).status, 201);
  await s.settle();
  assert.equal(apnsConfig({} as Env), null);
  assert.equal(apnsConfig({ APNS_KEY: "k", APNS_KEY_ID: "i", APNS_TEAM_ID: "t" } as Env), null);
});

test("410・BadDeviceToken の端末は台帳から消し、他の失敗は残す", async () => {
  const s = await withDevices();
  const T3 = "cc".repeat(32);
  await s.call("PUT", "/api/devices", { push_token: T3, member: "C" });
  s.sender.replies[T1] = { status: 410, reason: "Unregistered" };
  s.sender.replies[T2] = { status: 400, reason: "BadDeviceToken" };
  s.sender.replies[T3] = { status: 429, reason: "TooManyRequests" };
  await s.call("POST", "/api/items", { kind: "need", title: "玉ねぎ", by: "A" });
  await s.settle();
  const left = s.raw.prepare("SELECT push_token FROM devices").all().map((r: any) => r.push_token);
  assert.deepEqual(left, [T3]);
});

// ---- 本物の送り口（fetch をモック）と ES256 の JWT ----

async function p8(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const kp = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", kp.privateKey)) as ArrayBuffer);
  const b64 = Buffer.from(der).toString("base64").replace(/(.{64})/g, "$1\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`, publicKey: kp.publicKey };
}

function b64urlDecode(s: string): Uint8Array {
  return new Uint8Array(Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64"));
}

test("ES256 の JWT: ヘッダ・クレームが正しく、公開鍵で検証が通る", async () => {
  const { pem, publicKey } = await p8();
  const jwt = await makeProviderToken(await importP8(pem), "KEYID12345", "TEAMID1234", 1_800_000_000);
  const [h, c, sig] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(b64urlDecode(h)).toString()), { alg: "ES256", kid: "KEYID12345" });
  assert.deepEqual(JSON.parse(Buffer.from(b64urlDecode(c)).toString()), { iss: "TEAMID1234", iat: 1_800_000_000 });
  const raw = b64urlDecode(sig);
  assert.equal(raw.length, 64); // r||s
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, raw, new TextEncoder().encode(`${h}.${c}`));
  assert.ok(ok);
});

test("送り口: widgets の push-type・topic・本文で POST し、JWT は 50 分使い回す", async () => {
  resetTokenCacheForTest();
  const { pem } = await p8();
  const calls: { url: string; init: RequestInit }[] = [];
  const fakeFetch = async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return calls.length === 3
      ? new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: 400 })
      : new Response(null, { status: 200 });
  };
  let t = 1_800_000_000_000;
  const cfg = apnsConfig({
    APNS_KEY: pem,
    APNS_KEY_ID: "KEYID12345",
    APNS_TEAM_ID: "TEAMID1234",
    APNS_BUNDLE_ID: "jp.kechiiiiin.kazoku-keijiban",
    APNS_ENV: "production",
  } as Env)!;
  const sender = httpApnsSender(cfg, fakeFetch, () => t);
  assert.deepEqual(await sender.send(T1), { status: 200 });
  t += 49 * 60 * 1000;
  await sender.send(T2);
  t += 2 * 60 * 1000; // 発行から 51 分
  assert.deepEqual(await sender.send(T1), { status: 400, reason: "BadDeviceToken" });

  assert.equal(calls[0].url, `https://api.push.apple.com/3/device/${T1}`);
  const h = calls[0].init.headers as Record<string, string>;
  assert.equal(h["apns-push-type"], "widgets");
  assert.equal(h["apns-topic"], "jp.kechiiiiin.kazoku-keijiban.push-type.widgets");
  assert.equal(widgetTopic("x"), "x.push-type.widgets");
  assert.equal(calls[0].init.body, WIDGET_PAYLOAD);
  assert.deepEqual(JSON.parse(WIDGET_PAYLOAD), { aps: { "content-changed": true } });
  const auth = (i: number) => (calls[i].init.headers as Record<string, string>).authorization;
  assert.match(auth(0), /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.equal(auth(0), auth(1)); // 49 分後は同じ JWT
  assert.notEqual(auth(1), auth(2)); // 51 分後は作り直す
});

test("APNS_ENV=development なら sandbox へ", () => {
  const cfg = apnsConfig({ APNS_KEY: "k", APNS_KEY_ID: "i", APNS_TEAM_ID: "t", APNS_BUNDLE_ID: "b", APNS_ENV: "development" } as Env)!;
  assert.equal(cfg.host, "api.sandbox.push.apple.com");
});
