// ボードの読み書き（D1）。HTTP のことは app.ts、「今日」の数え方は day.ts。
import { boardDay, DEFAULT_RESET_TIME, nextResetAt, parseResetTime } from "./day.ts";

export type Kind = "daily" | "need";

export interface Done {
  by: string;
  at: string;
}

export interface BoardItem {
  id: number;
  kind: Kind;
  title: string;
  created_by: string;
  done: Done | null;
}

export interface Board {
  board_day: string;
  reset_time: string;
  /** 次に戻る時刻（ISO 8601・UTC）。ウィジェットはここでタイムラインを描き直す */
  next_reset_at: string;
  members: string[];
  daily: BoardItem[];
  needs: BoardItem[];
}

export const TITLE_MAX = 60;

/** 押す人の候補（secret の MEMBERS）。大小・表記はそのまま、空白と空要素だけ落とす */
export function parseMembers(raw: string | undefined): string[] {
  return (raw ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

/** 題名をならす（前後の空白・改行・制御文字）。空・長すぎは null */
export function normalizeTitle(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const t = raw.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
  if (!t || [...t].length > TITLE_MAX) return null;
  return t;
}

export function isKind(v: unknown): v is Kind {
  return v === "daily" || v === "need";
}

export async function getResetTime(db: D1Database): Promise<string> {
  const row = await db.prepare("SELECT value FROM settings WHERE key = 'reset_time'").first<{ value: string }>();
  const v = row?.value ?? DEFAULT_RESET_TIME;
  return parseResetTime(v) === null ? DEFAULT_RESET_TIME : v;
}

export async function setResetTime(db: D1Database, value: string): Promise<void> {
  await db
    .prepare("INSERT INTO settings (key, value) VALUES ('reset_time', ?1) ON CONFLICT (key) DO UPDATE SET value = excluded.value")
    .bind(value)
    .run();
}

type Row = {
  id: number;
  kind: Kind;
  title: string;
  created_by: string;
  c_day: string | null;
  c_by: string | null;
  c_at: string | null;
};

export async function getBoard(db: D1Database, now: Date, members: string[]): Promise<Board> {
  const resetTime = await getResetTime(db);
  const today = boardDay(now, resetTime);
  // 毎日のことは今日の印だけ、必要なものは（1つしか持たない）印を日付によらず拾う
  const { results } = await db
    .prepare(
      `SELECT i.id, i.kind, i.title, i.created_by, c.board_day AS c_day, c.by AS c_by, c.at AS c_at
         FROM items i
         LEFT JOIN checks c ON c.item_id = i.id AND (i.kind = 'need' OR c.board_day = ?1)
        WHERE i.archived_at IS NULL
        ORDER BY i.sort, i.id`,
    )
    .bind(today)
    .all<Row>();
  const daily: BoardItem[] = [];
  const needs: BoardItem[] = [];
  for (const r of results) {
    // 必要なもので、✓ を付けた board_day が今日より前のものは出さない（削除扱い）
    if (r.kind === "need" && r.c_day !== null && r.c_day < today) continue;
    const item: BoardItem = {
      id: Number(r.id),
      kind: r.kind,
      title: r.title,
      created_by: r.created_by,
      done: r.c_by !== null && r.c_at !== null ? { by: r.c_by, at: r.c_at } : null,
    };
    (r.kind === "daily" ? daily : needs).push(item);
  }
  return { board_day: today, reset_time: resetTime, next_reset_at: nextResetAt(now, resetTime).toISOString(), members, daily, needs };
}

/** 前の board_day に ✓ が付いた必要なものを外す（一覧からはもう消えているものの後片付け） */
export async function sweepNeeds(db: D1Database, now: Date): Promise<void> {
  const today = boardDay(now, await getResetTime(db));
  await db
    .prepare(
      `UPDATE items SET archived_at = ?2
        WHERE kind = 'need' AND archived_at IS NULL
          AND id IN (SELECT item_id FROM checks WHERE board_day < ?1)`,
    )
    .bind(today, now.toISOString())
    .run();
}

export async function addItem(db: D1Database, kind: Kind, title: string, by: string, now: Date): Promise<number> {
  const row = await db
    .prepare(
      `INSERT INTO items (kind, title, created_by, created_at, sort)
       VALUES (?1, ?2, ?3, ?4, (SELECT COALESCE(MAX(sort), 0) + 1 FROM items))
       RETURNING id`,
    )
    .bind(kind, title, by, now.toISOString())
    .first<{ id: number }>();
  return Number(row!.id);
}

type LiveItem = { id: number; kind: Kind };

async function liveItem(db: D1Database, id: number): Promise<LiveItem | null> {
  return db.prepare("SELECT id, kind FROM items WHERE id = ?1 AND archived_at IS NULL").bind(id).first<LiveItem>();
}

export type ToggleResult = "checked" | "unchecked" | "not_found";

/** ○⇄✓。○ に戻したら印の行を消す */
export async function toggleItem(db: D1Database, id: number, by: string, now: Date): Promise<ToggleResult> {
  const item = await liveItem(db, id);
  if (!item) return "not_found";
  const today = boardDay(now, await getResetTime(db));
  if (item.kind === "daily") {
    const del = await db.prepare("DELETE FROM checks WHERE item_id = ?1 AND board_day = ?2").bind(id, today).run();
    if (del.meta.changes > 0) return "unchecked";
  } else {
    const del = await db.prepare("DELETE FROM checks WHERE item_id = ?1 AND board_day >= ?2").bind(id, today).run();
    if (del.meta.changes > 0) return "unchecked";
    // 前の日に ✓ が付いたもの＝もう一覧から消えたもの。押し直せない
    const old = await db.prepare("SELECT 1 AS x FROM checks WHERE item_id = ?1").bind(id).first();
    if (old) return "not_found";
  }
  await db
    .prepare("INSERT OR IGNORE INTO checks (item_id, board_day, by, at) VALUES (?1, ?2, ?3, ?4)")
    .bind(id, today, by, now.toISOString())
    .run();
  return "checked";
}

/** 項目を外す（行は残して archived_at を入れる） */
export async function archiveItem(db: D1Database, id: number, now: Date): Promise<boolean> {
  const r = await db
    .prepare("UPDATE items SET archived_at = ?2 WHERE id = ?1 AND archived_at IS NULL")
    .bind(id, now.toISOString())
    .run();
  return r.meta.changes > 0;
}

export function normalizePushToken(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const t = raw.trim().toLowerCase();
  return /^[0-9a-f]{16,400}$/.test(t) && t.length % 2 === 0 ? t : null;
}

export async function upsertDevice(db: D1Database, token: string, member: string, now: Date): Promise<void> {
  await db
    .prepare(
      `INSERT INTO devices (push_token, member, updated_at) VALUES (?1, ?2, ?3)
       ON CONFLICT (push_token) DO UPDATE SET member = excluded.member, updated_at = excluded.updated_at`,
    )
    .bind(token, member, now.toISOString())
    .run();
}

export async function listDeviceTokens(db: D1Database): Promise<string[]> {
  const { results } = await db.prepare("SELECT push_token FROM devices ORDER BY push_token").all<{ push_token: string }>();
  return results.map((r) => r.push_token);
}

export async function deleteDevice(db: D1Database, token: string): Promise<void> {
  await db.prepare("DELETE FROM devices WHERE push_token = ?1").bind(token).run();
}
