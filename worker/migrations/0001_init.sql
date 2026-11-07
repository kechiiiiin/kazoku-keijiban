-- 家族掲示板の初期スキーマ（設計: jinsei vault hestia/projects/家族掲示板設計.md）

-- 項目。kind = 'daily'（毎日のこと・戻り時刻に未完へ戻る）／'need'（必要なもの・✓ の翌 board_day に消える）
CREATE TABLE items (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  kind        TEXT    NOT NULL CHECK (kind IN ('daily', 'need')),
  title       TEXT    NOT NULL,
  created_by  TEXT    NOT NULL,
  created_at  TEXT    NOT NULL,            -- ISO 8601（UTC）
  archived_at TEXT,                        -- 外したら入る（行は消さない）
  sort        INTEGER NOT NULL DEFAULT 0   -- 当面は足した順（= id）。並べ替えは未決
);
CREATE INDEX items_live ON items (archived_at, kind, sort);

-- 済んだ印。board_day（YYYY-MM-DD・戻り時刻で区切った「今日」）ごとに1行。○ に戻したら行を消す
CREATE TABLE checks (
  item_id   INTEGER NOT NULL REFERENCES items (id),
  board_day TEXT    NOT NULL,
  by        TEXT    NOT NULL,
  at        TEXT    NOT NULL,
  PRIMARY KEY (item_id, board_day)
);

-- ボード全体の設定。reset_time = 'HH:MM'（Asia/Tokyo）
CREATE TABLE settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT INTO settings (key, value) VALUES ('reset_time', '04:00');

-- ウィジェット用プッシュ（WidgetKit・apns-push-type: widgets）のトークン。端末ごとに1行
CREATE TABLE devices (
  push_token TEXT PRIMARY KEY,   -- 16進の小文字
  member     TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- プッシュの間引き。seq = 変更のたびに +1、sent_seq = 最後に送った seq（1行だけ）
CREATE TABLE push_state (
  id       INTEGER PRIMARY KEY CHECK (id = 1),
  seq      INTEGER NOT NULL DEFAULT 0,
  sent_seq INTEGER NOT NULL DEFAULT 0
);
INSERT INTO push_state (id, seq, sent_seq) VALUES (1, 0, 0);
