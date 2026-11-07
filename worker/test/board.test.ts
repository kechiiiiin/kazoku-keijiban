// API の一通り（受け入れ条件1）と、必要なものが ✓ の翌 board_day に消えること（受け入れ条件3）
import { test } from "node:test";
import assert from "node:assert/strict";
import { setup } from "./helpers.ts";

test("一覧: 空のボードと押す人の候補", async () => {
  const s = setup();
  const r = await s.call("GET", "/api/board");
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, {
    board_day: "2026-11-07",
    reset_time: "04:00",
    next_reset_at: "2026-11-07T19:00:00.000Z",
    members: ["A", "B", "C", "D"],
    daily: [],
    needs: [],
  });
});

test("足す: 種類ごとに分かれ、足した順に並ぶ", async () => {
  const s = setup();
  await s.call("POST", "/api/items", { kind: "daily", title: "風呂掃除", by: "A" });
  await s.call("POST", "/api/items", { kind: "need", title: "  玉ねぎ\n", by: "B" });
  const r = await s.call("POST", "/api/items", { kind: "daily", title: "洗濯物たたむ", by: "C" });
  assert.equal(r.status, 201);
  assert.deepEqual(r.json.daily.map((i: any) => i.title), ["風呂掃除", "洗濯物たたむ"]);
  assert.deepEqual(r.json.needs.map((i: any) => [i.title, i.created_by, i.done]), [["玉ねぎ", "B", null]]);
});

test("足す: 不正な入力は 400", async () => {
  const s = setup();
  const cases: [unknown, string][] = [
    [{ kind: "weekly", title: "x", by: "A" }, "bad_kind"],
    [{ kind: "need", title: "   ", by: "A" }, "bad_title"],
    [{ kind: "need", title: "あ".repeat(61), by: "A" }, "bad_title"],
    [{ kind: "need", title: 1, by: "A" }, "bad_title"],
    [{ kind: "need", title: "x", by: "Z" }, "bad_member"],
    [{ kind: "need", title: "x" }, "bad_member"],
  ];
  for (const [b, e] of cases) assert.deepEqual(await s.call("POST", "/api/items", b), { status: 400, json: { error: e } }, JSON.stringify(b));
  assert.equal((await s.call("POST", "/api/items", { kind: "need", title: "あ".repeat(60), by: "A" })).status, 201);
});

test("MEMBERS が空なら書き込みは 400（名前を選べない）", async () => {
  const s = setup({ env: { MEMBERS: "" } });
  assert.equal((await s.call("POST", "/api/items", { kind: "need", title: "x", by: "A" })).status, 400);
});

test("○⇄✓: 押した人の名前が付き、もう一度押すと ○ に戻る（行が消える）", async () => {
  const s = setup();
  const id = (await s.call("POST", "/api/items", { kind: "daily", title: "風呂掃除", by: "A" })).json.daily[0].id;
  let r = await s.call("POST", `/api/items/${id}/toggle`, { by: "C" });
  assert.equal(r.status, 200);
  assert.equal(r.json.daily[0].done.by, "C");
  assert.equal(r.json.daily[0].done.at, "2026-11-07T03:00:00.000Z");
  r = await s.call("POST", `/api/items/${id}/toggle`, { by: "D" });
  assert.equal(r.json.daily[0].done, null);
  const n = s.raw.prepare("SELECT COUNT(*) AS n FROM checks").get() as { n: number };
  assert.equal(n.n, 0);
});

test("○⇄✓: 知らない id・外した項目は 404、名前が無ければ 400", async () => {
  const s = setup();
  assert.equal((await s.call("POST", "/api/items/99/toggle", { by: "A" })).status, 404);
  assert.equal((await s.call("POST", "/api/items/abc/toggle", { by: "A" })).status, 404);
  const id = (await s.call("POST", "/api/items", { kind: "daily", title: "x", by: "A" })).json.daily[0].id;
  assert.equal((await s.call("POST", `/api/items/${id}/toggle`, {})).status, 400);
  await s.call("DELETE", `/api/items/${id}`);
  assert.equal((await s.call("POST", `/api/items/${id}/toggle`, { by: "A" })).status, 404);
});

test("外す: 一覧から消え、二度目は 404", async () => {
  const s = setup();
  const id = (await s.call("POST", "/api/items", { kind: "daily", title: "x", by: "A" })).json.daily[0].id;
  const r = await s.call("DELETE", `/api/items/${id}`);
  assert.equal(r.status, 200);
  assert.deepEqual(r.json.daily, []);
  assert.equal((await s.call("DELETE", `/api/items/${id}`)).status, 404);
});

test("必要なもの: ✓ の日のうちは ✓ のまま残り、翌 board_day に消える", async () => {
  const s = setup({ now: "2026-11-07T03:00:00Z" }); // 11/7 12:00 JST
  const r0 = await s.call("POST", "/api/items", { kind: "need", title: "玉ねぎ", by: "A" });
  await s.call("POST", "/api/items", { kind: "need", title: "単4電池", by: "A" });
  const id = r0.json.needs[0].id;
  await s.call("POST", `/api/items/${id}/toggle`, { by: "B" });

  s.clock.set("2026-11-07T18:59:00Z"); // 11/8 03:59 JST（まだ 11/7）
  let b = (await s.call("GET", "/api/board")).json;
  assert.deepEqual(b.needs.map((i: any) => [i.title, i.done?.by ?? null]), [["玉ねぎ", "B"], ["単4電池", null]]);

  s.clock.set("2026-11-07T19:00:00Z"); // 11/8 04:00 JST
  b = (await s.call("GET", "/api/board")).json;
  assert.deepEqual(b.needs.map((i: any) => i.title), ["単4電池"]);
  // 消えたものは押し直せない
  assert.equal((await s.call("POST", `/api/items/${id}/toggle`, { by: "A" })).status, 404);
  // 書き込みのついでに外される（後片付け）
  await s.call("POST", "/api/items", { kind: "need", title: "牛乳", by: "A" });
  const row = s.raw.prepare("SELECT archived_at FROM items WHERE id = ?").get(id) as { archived_at: string | null };
  assert.equal(row.archived_at, "2026-11-07T19:00:00.000Z");
});

test("必要なもの: ✓ を同じ日に外せば ○ に戻り、翌日も残る", async () => {
  const s = setup();
  const id = (await s.call("POST", "/api/items", { kind: "need", title: "玉ねぎ", by: "A" })).json.needs[0].id;
  await s.call("POST", `/api/items/${id}/toggle`, { by: "B" });
  await s.call("POST", `/api/items/${id}/toggle`, { by: "B" });
  s.clock.set("2026-11-08T03:00:00Z");
  const b = (await s.call("GET", "/api/board")).json;
  assert.deepEqual(b.needs.map((i: any) => [i.title, i.done]), [["玉ねぎ", null]]);
});

test("必要なもの: ✓ が付かないものは日をまたいでも残る", async () => {
  const s = setup();
  await s.call("POST", "/api/items", { kind: "need", title: "玉ねぎ", by: "A" });
  s.clock.set("2026-11-20T03:00:00Z");
  assert.equal((await s.call("GET", "/api/board")).json.needs.length, 1);
});

test("端末の登録: トークンは小文字にならして上書き、不正は 400", async () => {
  const s = setup();
  const tok = "AB".repeat(32);
  assert.deepEqual(await s.call("PUT", "/api/devices", { push_token: tok, member: "A" }), { status: 200, json: { ok: true } });
  await s.call("PUT", "/api/devices", { push_token: tok, member: "B" });
  const rows = s.raw.prepare("SELECT push_token, member FROM devices").all();
  assert.deepEqual(rows.map((r: any) => [r.push_token, r.member]), [["ab".repeat(32), "B"]]);
  assert.equal((await s.call("PUT", "/api/devices", { push_token: "xyz", member: "A" })).status, 400);
  assert.equal((await s.call("PUT", "/api/devices", { push_token: tok, member: "Z" })).status, 400);
});
