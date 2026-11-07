// 受け入れ条件2: board_day の境目（戻り時刻の前後1分・戻り時刻の変更）
import { test } from "node:test";
import assert from "node:assert/strict";
import { boardDay, nextResetAt, parseResetTime } from "../src/day.ts";
import { setup } from "./helpers.ts";

// JST = UTC+9。11/8 04:00 JST = 11/7 19:00Z
test("4:00 戻り: 3:59 は前の日、4:00 から次の日", () => {
  assert.equal(boardDay(new Date("2026-11-07T18:59:00Z"), "04:00"), "2026-11-07"); // 11/8 03:59 JST
  assert.equal(boardDay(new Date("2026-11-07T18:59:59.999Z"), "04:00"), "2026-11-07");
  assert.equal(boardDay(new Date("2026-11-07T19:00:00Z"), "04:00"), "2026-11-08"); // 11/8 04:00 JST
  assert.equal(boardDay(new Date("2026-11-07T19:01:00Z"), "04:00"), "2026-11-08"); // 11/8 04:01 JST
});

test("0:00 戻り・23:59 戻りの端", () => {
  assert.equal(boardDay(new Date("2026-11-07T14:59:00Z"), "00:00"), "2026-11-07"); // 11/7 23:59 JST
  assert.equal(boardDay(new Date("2026-11-07T15:00:00Z"), "00:00"), "2026-11-08"); // 11/8 00:00 JST
  assert.equal(boardDay(new Date("2026-11-08T14:58:00Z"), "23:59"), "2026-11-07"); // 11/8 23:58 JST
  assert.equal(boardDay(new Date("2026-11-08T14:59:00Z"), "23:59"), "2026-11-08"); // 11/8 23:59 JST
});

test("月・年をまたぐ", () => {
  assert.equal(boardDay(new Date("2026-12-31T18:59:00Z"), "04:00"), "2026-12-31"); // 1/1 03:59 JST
  assert.equal(boardDay(new Date("2026-12-31T19:00:00Z"), "04:00"), "2027-01-01");
});

test("戻り時刻を変えると同じ時刻でも board_day が変わる", () => {
  const t = new Date("2026-11-07T20:30:00Z"); // 11/8 05:30 JST
  assert.equal(boardDay(t, "04:00"), "2026-11-08");
  assert.equal(boardDay(t, "06:00"), "2026-11-07");
});

test("次に戻る時刻", () => {
  assert.equal(nextResetAt(new Date("2026-11-07T18:59:00Z"), "04:00").toISOString(), "2026-11-07T19:00:00.000Z");
  assert.equal(nextResetAt(new Date("2026-11-07T19:00:00Z"), "04:00").toISOString(), "2026-11-08T19:00:00.000Z");
  assert.equal(nextResetAt(new Date("2026-11-07T03:00:00Z"), "06:30").toISOString(), "2026-11-07T21:30:00.000Z");
});

test("戻り時刻の形", () => {
  assert.equal(parseResetTime("04:00"), 240);
  assert.equal(parseResetTime("23:59"), 23 * 60 + 59);
  for (const bad of ["4:00", "24:00", "04:60", "0400", "", null, 4]) assert.equal(parseResetTime(bad), null, String(bad));
});

test("API: 毎日のことの ✓ は戻り時刻の1分前まで残り、戻り時刻で ○ に戻る", async () => {
  const s = setup({ now: "2026-11-07T03:00:00Z" });
  const add = await s.call("POST", "/api/items", { kind: "daily", title: "風呂掃除", by: "A" });
  const id = add.json.daily[0].id;
  await s.call("POST", `/api/items/${id}/toggle`, { by: "B" });
  s.clock.set("2026-11-07T18:59:00Z"); // 11/8 03:59 JST
  let b = (await s.call("GET", "/api/board")).json;
  assert.equal(b.board_day, "2026-11-07");
  assert.equal(b.daily[0].done.by, "B");
  s.clock.set("2026-11-07T19:00:00Z"); // 11/8 04:00 JST
  b = (await s.call("GET", "/api/board")).json;
  assert.equal(b.board_day, "2026-11-08");
  assert.equal(b.daily[0].done, null);
  assert.equal(b.next_reset_at, "2026-11-08T19:00:00.000Z");
});

test("API: 戻り時刻を 6:00 に変えると 5:00 の時点ではまだ前の日", async () => {
  const s = setup({ now: "2026-11-07T03:00:00Z" });
  const id = (await s.call("POST", "/api/items", { kind: "daily", title: "洗濯物たたむ", by: "A" })).json.daily[0].id;
  await s.call("POST", `/api/items/${id}/toggle`, { by: "A" });
  const r = await s.call("PUT", "/api/settings/reset-time", { reset_time: "06:00" });
  assert.equal(r.status, 200);
  assert.equal(r.json.reset_time, "06:00");
  s.clock.set("2026-11-07T20:00:00Z"); // 11/8 05:00 JST
  let b = (await s.call("GET", "/api/board")).json;
  assert.equal(b.board_day, "2026-11-07");
  assert.equal(b.daily[0].done.by, "A");
  s.clock.set("2026-11-07T21:00:00Z"); // 11/8 06:00 JST
  b = (await s.call("GET", "/api/board")).json;
  assert.equal(b.board_day, "2026-11-08");
  assert.equal(b.daily[0].done, null);
});

test("API: 戻り時刻の不正な値は 400", async () => {
  const s = setup();
  for (const v of ["4:00", "25:00", "", 4, null]) {
    const r = await s.call("PUT", "/api/settings/reset-time", { reset_time: v });
    assert.deepEqual(r, { status: 400, json: { error: "bad_reset_time" } }, String(v));
  }
});
