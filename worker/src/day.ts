// 「今日」（board_day）の数え方。
// board_day = いまの時刻（Asia/Tokyo）から戻り時刻を引いた日付。4:00 戻りなら 11/8 3:59 は 11/7、4:00 から 11/8。
// 日本は夏時間が無いので UTC+9 固定で計算する（Intl を使わない＝テストで揺れない）。

const JST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

export const DEFAULT_RESET_TIME = "04:00";

/** 'HH:MM'（00:00〜23:59）なら分に。それ以外は null */
export function parseResetTime(raw: unknown): number | null {
  if (typeof raw !== "string") return null;
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(raw);
  if (!m) return null;
  return Number(m[1]) * 60 + Number(m[2]);
}

function ymd(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/** いまの board_day（YYYY-MM-DD） */
export function boardDay(now: Date, resetTime: string): string {
  const minutes = parseResetTime(resetTime) ?? parseResetTime(DEFAULT_RESET_TIME)!;
  return ymd(now.getTime() + JST_OFFSET_MS - minutes * 60_000);
}

/** 次に戻る時刻（UTC の Date）。ウィジェットのタイムラインの次の更新に使う */
export function nextResetAt(now: Date, resetTime: string): Date {
  const minutes = parseResetTime(resetTime) ?? parseResetTime(DEFAULT_RESET_TIME)!;
  const day = boardDay(now, resetTime); // この board_day が終わる時刻 = 翌日の戻り時刻（JST）
  const startOfDayJstAsUtc = Date.parse(`${day}T00:00:00Z`) - JST_OFFSET_MS;
  return new Date(startOfDayJstAsUtc + DAY_MS + minutes * 60_000);
}
