#!/bin/bash
# 家族掲示板の Cloudflare Access を用意する一回きりの設定。秘密の値は画面に出さず、キーチェーンにだけ置く。
# 何度流しても同じ結果になる（ただしトークンの秘密は毎回回し直すので、配った iPhone には入れ直しが要る）。
#
#   1. サービストークン kazoku-keijiban-family を作る（あれば回し直す）→ キーチェーン kazoku-keijiban-token
#   2. Access アプリ「kazoku-keijiban」（Self-hosted）で kazoku-keijiban.kechiiiiin.com を守る（無ければ作る）
#   3. そのアプリのポリシーを「Service Auth でこのトークンだけ」にする
#   4. Worker secret CF_ACCESS_AUD・ACCESS_SERVICE_CLIENT_IDS を設定する
#
# 要るもの: キーチェーン cloudflare-admin-token（Access 編集）・cloudflare-deploy-token（Workers 編集）
set -euo pipefail

TOKEN_NAME=kazoku-keijiban-family
KC=kazoku-keijiban-token
HOST=kazoku-keijiban.kechiiiiin.com
APP_NAME=kazoku-keijiban

cd "$(dirname "$0")/../worker"
ADMIN=$(security find-generic-password -s cloudflare-admin-token -w)
api() { curl -sS -H "Authorization: Bearer $ADMIN" -H "Content-Type: application/json" "$@"; }
ok() { python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d.get("success") else (print(d.get("errors"),file=sys.stderr) or 1))'; }
field() { python3 -c "import sys,json;print(json.load(sys.stdin)['result']['$1'])"; }

ACC=$(api "https://api.cloudflare.com/client/v4/zones?name=kechiiiiin.com" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"][0]["account"]["id"])')
B=https://api.cloudflare.com/client/v4/accounts/$ACC/access

# 1. トークン
TID=$(api "$B/service_tokens" | python3 -c "import sys,json;print(next((t['id'] for t in json.load(sys.stdin)['result'] if t['name']=='$TOKEN_NAME'),''))")
if [ -z "$TID" ]; then
  R=$(api -X POST "$B/service_tokens" -d "{\"name\":\"$TOKEN_NAME\",\"duration\":\"forever\"}")
else
  R=$(api -X POST "$B/service_tokens/$TID/rotate")
fi
echo "$R" | ok
TID=$(echo "$R" | field id)
CID=$(echo "$R" | field client_id)
security add-generic-password -U -s "$KC" -a client-id -w "$CID"
security add-generic-password -U -s "$KC" -a client-secret -w "$(echo "$R" | field client_secret)"
unset R
echo "1. トークン $TOKEN_NAME をキーチェーン $KC に保存"

# 2. アプリ
APP=$(api "$B/apps" | python3 -c "import sys,json;print(next((a['id'] for a in json.load(sys.stdin)['result'] if a.get('name')=='$APP_NAME'),''))")
BODY="{\"name\":\"$APP_NAME\",\"type\":\"self_hosted\",\"domain\":\"$HOST\",\"destinations\":[{\"type\":\"public\",\"uri\":\"$HOST\"}],\"session_duration\":\"24h\",\"app_launcher_visible\":false}"
if [ -z "$APP" ]; then
  R=$(api -X POST "$B/apps" -d "$BODY")
else
  R=$(api -X PUT "$B/apps/$APP" -d "$BODY")
fi
echo "$R" | ok
APP=$(echo "$R" | field id)
AUD=$(echo "$R" | field aud)
echo "2. Access アプリ $APP_NAME（$HOST）"

# 3. ポリシー（アプリに付いたものを Service Auth の1本にそろえる）
P="{\"name\":\"family service token\",\"decision\":\"non_identity\",\"precedence\":1,\"include\":[{\"service_token\":{\"token_id\":\"$TID\"}}]}"
PID=$(api "$B/apps/$APP/policies" | python3 -c "import sys,json;r=json.load(sys.stdin).get('result') or [];print(r[0]['id'] if r else '')")
if [ -z "$PID" ]; then
  api -X POST "$B/apps/$APP/policies" -d "$P" | ok
else
  api -X PUT "$B/apps/$APP/policies/$PID" -d "$P" | ok
fi
echo "3. ポリシー: Service Auth（$TOKEN_NAME だけ）"

# 4. Worker secret
export CLOUDFLARE_API_TOKEN=$(security find-generic-password -s cloudflare-deploy-token -w)
printf '%s' "$AUD" | npx wrangler secret put CF_ACCESS_AUD >/dev/null
printf '%s' "$CID" | npx wrangler secret put ACCESS_SERVICE_CLIENT_IDS >/dev/null
echo "4. Worker secret CF_ACCESS_AUD・ACCESS_SERVICE_CLIENT_IDS を設定"
echo "完了"
