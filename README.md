# 家族掲示板（kazoku-keijiban）

家族の iPhone のウィジェットで「毎日の家事の完了／未完」と「必要なもの」を共有する。

- **毎日のこと** … 戻り時刻（既定 4:00・Asia/Tokyo）に ○ へ戻る
- **必要なもの** … 一度きり。✓ を付けた次の戻り時刻で一覧から消える
- ウィジェット（大）の ○ を押すと、アプリを開かずに ✓ と押した人の名前が付く
- Siri: 「家族掲示板に足して」→「何を足しますか？」→「玉ねぎ」で必要なものに入る
- 変更すると Worker が APNs のウィジェット用プッシュ（`apns-push-type: widgets`）を送り、他の家族のウィジェットも描き直される

```
worker/   Cloudflare Worker（Hono・TypeScript）＋ D1 マイグレーション＋テスト（node --test）
ios/      XcodeGen の project.yml・SwiftUI アプリ・WidgetKit 拡張・App Intents
```

## 仕組み（要点）

| 項目 | どうなっているか |
| --- | --- |
| 「今日」 | `board_day` = いまの時刻（JST）− 戻り時刻 の日付。✓ は `board_day` ごとに記録するので cron は要らない |
| 認証 | Cloudflare Access のサービストークン。Worker は関所（sekisho）の `verify(token, aud, { allowServiceTokens: true })` で確かめ、Client ID を `ACCESS_SERVICE_CLIENT_IDS` と照合（無し・不正は 401、許可外は 403） |
| 押す人の名前 | Worker の secret `MEMBERS`（ソースに家族の名前を置かない）。アプリは `GET /api/board` の `members` から選ぶ |
| プッシュの間引き | 変更のたびに `push_state.seq` を +1、3 秒待って自分が最後の変更なら送る（D1 の1行で決めるので二重送信しない） |
| APNs | `.p8` の ES256 で JWT を作り 50 分使い回す。410／BadDeviceToken の端末は台帳から消す |

### API

| メソッド | パス | 本文 |
| --- | --- | --- |
| GET | `/api/board` | — |
| POST | `/api/items` | `{ kind: "daily"\|"need", title, by }` |
| POST | `/api/items/:id/toggle` | `{ by }` |
| DELETE | `/api/items/:id` | — |
| PUT | `/api/settings/reset-time` | `{ reset_time: "HH:MM" }` |
| PUT | `/api/devices` | `{ push_token, member }` |

変更系は最新の一覧（GET と同じ形）を返す。

## 開発

```sh
cd worker
npm install
npm run check          # tsc --noEmit と テスト

cp .dev.vars.example .dev.vars   # ローカルは認証を迂回（localhost かつ --define __LOCAL_DEV__ のときだけ）
npm run dev            # http://127.0.0.1:8791

cd ../ios
make sim               # xcodegen generate → シミュレータ向けビルド
make shots             # ローカルの Worker を見て、アプリとウィジェットのプレビューを撮る（build-sim/shots/）
```

DEBUG ビルドだけ、起動引数 `-kkBaseURL http://127.0.0.1:8791` でつなぎ先を差し替えられる（App Group に写すのでウィジェットも同じ先を見る）。`-kkWidgetPreview` でウィジェットと同じ描画をアプリ内に出す。

## セットアップ（初回）

値はここに書かない。secret は `wrangler secret put`、ローカルは `.dev.vars`（コミットしない）。

### 埋めるところ（仮の値が入っている）

| ファイル | 項目 | 何を入れるか |
| --- | --- | --- |
| `worker/wrangler.toml` | `d1_databases.database_id` | `wrangler d1 create kazoku-keijiban` の出力 |
| `worker/wrangler.toml` | `routes.pattern` | Worker を置くドメイン（例: `kazoku-keijiban.<自分のドメイン>`） |
| `ios/project.yml` | `KAZOKU_SERVER_URL` | 上のドメインの `https://…` |
| `~/.config/kazoku-keijiban/team-id` | 1行 | 有料チームの Team ID（Makefile が `KAZOKU_TEAM_ID` に渡す）。分かれば `project.yml` に直書きでもよい |

### 1. D1

```sh
cd worker
npx wrangler d1 create kazoku-keijiban          # → database_id を wrangler.toml へ
npx wrangler d1 migrations apply kazoku-keijiban --remote
```

### 2. Cloudflare Access

`scripts/setup-access.sh` を1回流すと 1〜4 と Worker の secret（CF_ACCESS_AUD・ACCESS_SERVICE_CLIENT_IDS）まで済む（自動モードでは止まるので手で流す）。手で作る場合:

1. Access のアプリケーション（Self-hosted）を作り、上のドメインを守る
2. サービストークンを1本作る（Client ID / Client Secret を控える）
3. アプリのポリシーに「Service Auth」でそのトークンを許可する
4. アプリの **AUD タグ**を控える

### 3. Worker の secret

| 名前 | 中身 |
| --- | --- |
| `CF_ACCESS_AUD` | Access アプリの AUD タグ |
| `ACCESS_SERVICE_CLIENT_IDS` | 通すサービストークンの Client ID（カンマ区切り） |
| `MEMBERS` | 押す人の候補（カンマ区切り・アプリの名前選びに出る順） |
| `APNS_KEY` | APNs の `.p8` の中身（PEM まるごと） |
| `APNS_KEY_ID` | その鍵の Key ID |
| `APNS_TEAM_ID` | Apple Developer の Team ID |

```sh
npx wrangler secret put CF_ACCESS_AUD
# …同様に
npx wrangler secret put APNS_KEY < /path/to/AuthKey_XXXXXXXXXX.p8
```

`APNS_*` が欠けているとプッシュは送らない（一覧の読み書きは動く）。`[vars]` の `APNS_ENV` は TestFlight・App Store なら `production`、Xcode から直接入れた開発ビルドで試すときだけ `development`。

関所（sekisho）が同じアカウントにデプロイ済みであること（Service Binding `SEKISHO`）。

### 4. APNs 鍵

Apple Developer → Certificates, Identifiers & Profiles → Keys で「Apple Push Notifications service (APNs)」を有効にした鍵を作り、`.p8` をダウンロードする（1回しか落とせない）。APNs の鍵はチーム全体で使えるので、同じチームに既存の鍵があればそれを使ってよい。

### 5. iOS

- bundle id: アプリ `jp.kechiiiiin.kazoku-keijiban`、ウィジェット `jp.kechiiiiin.kazoku-keijiban.widget`
- App Group: `group.jp.kechiiiiin.kazoku-keijiban`（アプリとウィジェットの両方。サービストークンもこのグループの Keychain に入る）
- Push Notifications（`aps-environment`）: アプリとウィジェットの両方
- Xcode の自動署名で App ID・App Group・Push を作らせる。TestFlight へはアーカイブして上げる
- サービストークンは、アプリの設定画面に Client ID / Secret を貼る（家族の iPhone）。Mac から流すときはアプリのコンテナの `tmp/` に `kk-import-access-client-id` / `kk-import-access-client-secret` を置くと次の起動で Keychain へ移して消す

## 決まっていない

- 項目の並べ替え（当面は足した順）
