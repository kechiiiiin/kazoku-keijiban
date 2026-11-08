# 家族掲示板 iOS — よく使う手順
#
#   make generate   xcodegen で .xcodeproj を作る（生成物はコミットしない）
#   make sim        シミュレータ向けにビルドだけ通す（署名なし・Team ID 不要）
#   make shots      シミュレータで起動してスクリーンショット（先に ../worker で npm run dev）
#   make archive    TestFlight 向けアーカイブ（Release・自動署名）。サービストークンをこの Mac のキーチェーンから埋め込む
#   make upload     （雛形）アーカイブを App Store Connect へ上げる
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

.PHONY: generate sim shots icon clean archive upload

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

## キーチェーン → Secrets.xcconfig（gitignore）→ generate → archive。値は表示しない。無ければ失敗
archive:
	@test -n "$(TEAM)" || { echo "❌ Team ID がありません（$(CONF)/team-id か make archive TEAM=XXXXXXXXXX）"; exit 1; }
	@umask 077; \
	cid=$$(security find-generic-password -s $(KC_SERVICE) -a client-id -w 2>/dev/null) && [ -n "$$cid" ] || { echo "❌ キーチェーンに $(KC_SERVICE) / client-id がありません（scripts/setup-access.sh のトークンを入れてください）"; exit 1; }; \
	sec=$$(security find-generic-password -s $(KC_SERVICE) -a client-secret -w 2>/dev/null) && [ -n "$$sec" ] || { echo "❌ キーチェーンに $(KC_SERVICE) / client-secret がありません"; exit 1; }; \
	printf 'KK_ACCESS_CLIENT_ID = %s\nKK_ACCESS_CLIENT_SECRET = %s\n' "$$cid" "$$sec" > $(SECRETS); \
	echo "✅ $(SECRETS) を生成した（値は表示しない・gitignore 済み）"
	xcodegen generate
	rm -rf build/KazokuKeijiban.xcarchive
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	  -destination 'generic/platform=iOS' -archivePath $(ARCHIVE) \
	  -allowProvisioningUpdates archive
	@echo "✅ $(ARCHIVE) ができた。上げるなら Xcode Organizer か make upload"

## （雛形・まだ流さない）App Store Connect へ upload。ExportOptions.plist（method: app-store-connect, destination: upload, teamID）が要る
upload:
	@test -f ExportOptions.plist || { echo "❌ ExportOptions.plist がありません"; exit 1; }
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist ExportOptions.plist \
	  -exportPath build/export -allowProvisioningUpdates

icon:
	swift scripts/gen-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

clean:
	rm -rf build build-sim build-check $(PROJECT)
	rm -f Secrets.xcconfig
