# 家族掲示板 iOS — よく使う手順
#
#   make generate   xcodegen で .xcodeproj を作る（生成物はコミットしない）
#   make sim        シミュレータ向けにビルドだけ通す（署名なし・Team ID 不要）
#   make shots      シミュレータで起動してスクリーンショット（先に ../worker で npm run dev）
#   make archive    TestFlight 向けアーカイブ（Release・自動署名）。サービストークンをこの Mac のキーチェーンから埋め込む
#   make export-testflight  .ipa を build/export/ に書き出す（送らない）
#   make upload     API キーで App Store Connect へ上げる（Release.local.env と .p8 が要る）
#   make release    archive → upload（ビルド番号は日時で自動）
#   make icon    アプリアイコンを描き直す
#
# Team ID は ~/.config/kazoku-keijiban/team-id（1行）か `make ... TEAM=XXXXXXXXXX`。

PROJECT = kazoku-keijiban.xcodeproj
SCHEME  = KazokuKeijiban
BUNDLE  = jp.kechiiiiin.kazoku-keijiban
CONF    = $(HOME)/.config/kazoku-keijiban
TEAM   ?= $(shell cat $(CONF)/team-id 2>/dev/null)
export KAZOKU_TEAM_ID = $(TEAM)
SIMNAME = Kazoku-Sim
SIMTYPE = iPhone 17
LOCAL   = http://127.0.0.1:8791
SHOTS   = build-sim/shots

ARCHIVE = build/KazokuKeijiban.xcarchive
# サービストークンの出どころ（ビルドする Mac のキーチェーン。読むだけで書き込まない）
KC_SERVICE ?= kazoku-keijiban-token
SECRETS = Secrets.xcconfig

.PHONY: generate sim shots icon clean archive upload export-testflight release require-team require-asc-key

generate:
	xcodegen generate

sim: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'generic/platform=iOS Simulator' -configuration Debug \
	  -derivedDataPath build-sim CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
	@echo "✅ シミュレータ向けのビルドは通る"

## ローカルの Worker（../worker で npm run dev・127.0.0.1:8791）を見てアプリとウィジェットのプレビューを撮る
shots: sim
	@xcrun simctl list devices | grep -q "$(SIMNAME) (" || xcrun simctl create "$(SIMNAME)" "$(SIMTYPE)" > /dev/null
	@xcrun simctl boot "$(SIMNAME)" 2>/dev/null || true
	xcrun simctl install "$(SIMNAME)" build-sim/Build/Products/Debug-iphonesimulator/KazokuKeijiban.app
	@mkdir -p $(SHOTS)
	xcrun simctl launch --terminate-running-process "$(SIMNAME)" $(BUNDLE) -kkBaseURL $(LOCAL) -kkMember A
	@sleep 4
	xcrun simctl io "$(SIMNAME)" screenshot $(SHOTS)/app.png
	xcrun simctl launch --terminate-running-process "$(SIMNAME)" $(BUNDLE) -kkBaseURL $(LOCAL) -kkMember A -kkWidgetPreview
	@sleep 4
	xcrun simctl io "$(SIMNAME)" screenshot $(SHOTS)/widget-preview.png
	@echo "✅ $(SHOTS)/ に保存した"

# 署名は API キー＋ -allowProvisioningUpdates の自動署名（縁側 engawa と同形）。
# xcodebuild の全文ログ（build/archive.log・build/export.log）には API キーのパスと Key ID が出る。build/ は gitignore 済み
RELEASE_ENV   = Release.local.env
EXPORT_DIR    = build/export
EXPORT_PLIST  = build/ExportOptions.generated.plist
RELEASE_DD    = build/release
DESTINATION  ?= export
# ビルド番号（CFBundleVersion）: 「年月日.1時分」（例 20261108.10930）。上げるたびに増える。BUILD_NUMBER= で上書き可。
# project.yml の CURRENT_PROJECT_VERSION（1）は開発用のまま書き換えない（コマンドラインの値は両ターゲットに効く）
BUILD_NUMBER ?= $(shell date +%Y%m%d.1%H%M)

# API キー（Release.local.env から読む。環境変数でも渡せる）。値は表示しない
env_value = $(strip $(shell sed -n 's/^$(1)=//p' $(RELEASE_ENV) 2>/dev/null | tail -1))
ASC_KEY_ID    ?= $(call env_value,ASC_KEY_ID)
ASC_ISSUER_ID ?= $(call env_value,ASC_ISSUER_ID)
ASC_KEY_PATH  ?= $(call env_value,ASC_KEY_PATH)
ifeq ($(strip $(ASC_KEY_PATH)),)
ASC_KEY_PATH := $(HOME)/.appstoreconnect/private_keys/AuthKey_$(ASC_KEY_ID).p8
endif
ASC_KEY_PATH := $(patsubst ~/%,$(HOME)/%,$(ASC_KEY_PATH))
ifneq ($(and $(ASC_KEY_ID),$(ASC_ISSUER_ID),$(wildcard $(ASC_KEY_PATH))),)
AUTH_FLAGS = -authenticationKeyPath "$(ASC_KEY_PATH)" -authenticationKeyID $(ASC_KEY_ID) -authenticationKeyIssuerID $(ASC_ISSUER_ID)
endif

require-team:
	@test -n "$(TEAM)" || { echo "❌ Team ID がありません（$(CONF)/team-id か TEAM=XXXXXXXXXX）"; exit 1; }

require-asc-key:
	@test -n "$(ASC_KEY_ID)" -a -n "$(ASC_ISSUER_ID)" || { echo "ASC_KEY_ID / ASC_ISSUER_ID がありません。Release.example.env を見て Release.local.env を作ってください"; exit 1; }
	@test -f "$(ASC_KEY_PATH)" || { echo "API キーがありません: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8"; exit 1; }

## キーチェーン → Secrets.xcconfig（gitignore）→ generate → archive。値は表示しない。無ければ失敗
archive: require-team require-asc-key
	@umask 077; \
	cid=$$(security find-generic-password -s $(KC_SERVICE) -a client-id -w 2>/dev/null) && [ -n "$$cid" ] || { echo "❌ キーチェーンに $(KC_SERVICE) / client-id がありません（scripts/setup-access.sh のトークンを入れてください）"; exit 1; }; \
	sec=$$(security find-generic-password -s $(KC_SERVICE) -a client-secret -w 2>/dev/null) && [ -n "$$sec" ] || { echo "❌ キーチェーンに $(KC_SERVICE) / client-secret がありません"; exit 1; }; \
	printf 'KK_ACCESS_CLIENT_ID = %s\nKK_ACCESS_CLIENT_SECRET = %s\n' "$$cid" "$$sec" > $(SECRETS); \
	echo "✅ $(SECRETS) を生成した（値は表示しない・gitignore 済み）"
	xcodegen generate
	@mkdir -p build
	rm -rf $(ARCHIVE)
	@echo "ビルド番号 $(BUILD_NUMBER) で archive します"
	@set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	  -destination 'generic/platform=iOS' -derivedDataPath $(RELEASE_DD) -archivePath $(ARCHIVE) \
	  -allowProvisioningUpdates $(AUTH_FLAGS) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) archive 2>&1 \
	  | tee build/archive.log | grep -E '(error|warning):|ARCHIVE (SUCCEEDED|FAILED)' ; \
	  grep -q 'ARCHIVE SUCCEEDED' build/archive.log || { echo "archive に失敗しました（全文は build/archive.log）"; exit 1; }
	@echo "できました: $(ARCHIVE)（ビルド $(BUILD_NUMBER)）。上げるなら make upload"

## .xcarchive から App Store Connect 向けの .ipa を build/export/ に書き出す（送らない）
export-testflight: require-team require-asc-key
	@test -d $(ARCHIVE) || { echo "$(ARCHIVE) がありません。先に make archive"; exit 1; }
	rm -rf $(EXPORT_DIR)
	@mkdir -p $(EXPORT_DIR)
	cp ExportOptions.plist $(EXPORT_PLIST)
	@plutil -replace teamID -string "$(TEAM)" $(EXPORT_PLIST)
	plutil -replace destination -string $(DESTINATION) $(EXPORT_PLIST)
	@set -o pipefail; xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportPath $(EXPORT_DIR) \
	  -exportOptionsPlist $(EXPORT_PLIST) -allowProvisioningUpdates $(AUTH_FLAGS) 2>&1 \
	  | tee build/export.log | grep -E '(error|warning):|EXPORT (SUCCEEDED|FAILED)|Upload|Uploaded|uploaded' ; \
	  grep -q 'EXPORT SUCCEEDED' build/export.log || { echo "export に失敗しました（全文は build/export.log）"; exit 1; }
	@if [ "$(DESTINATION)" = export ]; then ls -lh $(EXPORT_DIR)/*.ipa; else echo "App Store Connect へ上げました（処理が済むと TestFlight に出る）"; fi

## API キーで App Store Connect へ上げる（先に make archive）。アプリのレコードは App Store Connect で先に作っておく
upload: require-asc-key
	$(MAKE) export-testflight DESTINATION=upload

release: archive upload

icon:
	swift scripts/gen-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

clean:
	rm -rf build build-sim build-check $(PROJECT)
	rm -f Secrets.xcconfig
