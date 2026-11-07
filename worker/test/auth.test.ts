// 受け入れ条件1: サービストークンなし・許可外の Client ID は 401／403
import { test } from "node:test";
import assert from "node:assert/strict";
import { setup } from "./helpers.ts";
import type { Sekisho } from "../src/auth.ts";

const ROUTES: [string, string, unknown?][] = [
  ["GET", "/api/board"],
  ["POST", "/api/items", { kind: "need", title: "玉ねぎ", by: "A" }],
  ["POST", "/api/items/1/toggle", { by: "A" }],
  ["DELETE", "/api/items/1"],
  ["PUT", "/api/settings/reset-time", { reset_time: "05:00" }],
  ["PUT", "/api/devices", { push_token: "ab".repeat(32), member: "A" }],
];

test("トークンが無ければ全部の API が 401", async () => {
  const s = setup();
  for (const [m, p, b] of ROUTES) {
    const r = await s.call(m, p, b, null);
    assert.equal(r.status, 401, `${m} ${p}`);
    assert.deepEqual(r.json, { error: "unauthorized" });
  }
});

test("関所が否認したトークンは 401", async () => {
  const s = setup();
  for (const [m, p, b] of ROUTES) assert.equal((await s.call(m, p, b, "garbage.jwt")).status, 401, `${m} ${p}`);
});

test("許可外の Client ID は 403", async () => {
  const s = setup();
  for (const [m, p, b] of ROUTES) assert.equal((await s.call(m, p, b, "other.jwt")).status, 403, `${m} ${p}`);
});

test("ブラウザのユーザー（サービストークンでない）は 403", async () => {
  const s = setup();
  assert.equal((await s.call("GET", "/api/board", undefined, "user.jwt")).status, 403);
});

test("ACCESS_SERVICE_CLIENT_IDS が空なら 403（1本も通さない）", async () => {
  const s = setup({ env: { ACCESS_SERVICE_CLIENT_IDS: "" } });
  assert.equal((await s.call("GET", "/api/board")).status, 403);
});

test("許可された Client ID は通る（大小を無視）", async () => {
  const s = setup();
  assert.equal((await s.call("GET", "/api/board")).status, 200);
});

test("設定漏れ・関所の故障は 401（fail-closed）", async () => {
  assert.equal((await setup({ env: { CF_ACCESS_AUD: "" } }).call("GET", "/api/board")).status, 401);
  assert.equal((await setup({ env: { SEKISHO: undefined } }).call("GET", "/api/board")).status, 401);
  const broken: Sekisho = {
    verify: async () => {
      throw new Error("down");
    },
  };
  assert.equal((await setup({ env: { SEKISHO: broken } }).call("GET", "/api/board")).status, 401);
});

test("拒んだ要求では書き込まれず、プッシュも走らない", async () => {
  const s = setup();
  await s.call("POST", "/api/items", { kind: "need", title: "玉ねぎ", by: "A" }, "other.jwt");
  assert.equal(s.waits.length, 0);
  const row = s.raw.prepare("SELECT COUNT(*) AS n FROM items").get() as { n: number };
  assert.equal(row.n, 0);
});
