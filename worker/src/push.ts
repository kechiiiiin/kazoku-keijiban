// 変更のあと、登録済みの全端末へウィジェット用プッシュを送る（ctx.waitUntil の中で走る）。
//
// 間引き（ウィジェット用プッシュには日ごとの予算がある）: **最後の変更から DEBOUNCE_MS 静かになったら1回だけ送る**。
//   1. 変更のたびに push_state.seq を +1 して、自分の番号を覚える
//   2. DEBOUNCE_MS 待つ
//   3. `UPDATE ... SET sent_seq = 自分 WHERE seq = 自分 AND sent_seq < 自分` が1行変われば自分が最後＝送る。
//      後から変更が来ていれば seq が進んでいるので何もしない（その変更の側が送る）
// D1 の1行で決めるので、別の isolate で同時に走っても二重に送らない。
import { deleteDevice, listDeviceTokens } from "./board.ts";
import type { ApnsSender } from "./apns.ts";

export const DEBOUNCE_MS = 3000;

export interface PushDeps {
  sender: ApnsSender | null;
  debounceMs?: number;
  sleep?: (ms: number) => Promise<void>;
}

const realSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** 送らなくなる応答（端末がアプリを消した・トークンが別環境のもの） */
function isDeadToken(status: number, reason: string | undefined): boolean {
  return status === 410 || reason === "BadDeviceToken" || reason === "Unregistered" || reason === "DeviceTokenNotForTopic";
}

export type NotifyOutcome = { sent: number; skipped: "superseded" | "no_sender" | null };

export async function notifyChange(db: D1Database, deps: PushDeps): Promise<NotifyOutcome> {
  const row = await db.prepare("UPDATE push_state SET seq = seq + 1 WHERE id = 1 RETURNING seq").first<{ seq: number }>();
  const mine = Number(row?.seq ?? 0);
  await (deps.sleep ?? realSleep)(deps.debounceMs ?? DEBOUNCE_MS);
  const claim = await db
    .prepare("UPDATE push_state SET sent_seq = ?1 WHERE id = 1 AND seq = ?1 AND sent_seq < ?1")
    .bind(mine)
    .run();
  if (claim.meta.changes === 0) return { sent: 0, skipped: "superseded" };
  if (!deps.sender) return { sent: 0, skipped: "no_sender" };

  const tokens = await listDeviceTokens(db);
  let sent = 0;
  await Promise.all(
    tokens.map(async (t) => {
      try {
        const r = await deps.sender!.send(t);
        if (r.status >= 200 && r.status < 300) sent++;
        else if (isDeadToken(r.status, r.reason)) await deleteDevice(db, t);
        else console.warn(`apns: ${r.status} ${r.reason ?? ""}`);
      } catch (e) {
        console.warn("apns: " + (e instanceof Error ? e.name : "error"));
      }
    }),
  );
  return { sent, skipped: null };
}
