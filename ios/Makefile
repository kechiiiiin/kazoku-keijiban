# 家族掲示板 iOS — よく使う手順
#
#   make generate   xcodegen で .xcodeproj を作る（生成物はコミットしない）
#   make sim        シミュレータ向けにビルドだけ通す（署名なし・Team ID 不要）
#   make shots      シミュレータで起動してスクリーンショット（先に ../worker で npm run dev）
#   make icon       アプリアイコンを描き直す
#
# Team ID は ~/.config/kazoku-keijiban/team-id（1行）か `make ... TEAM=XXXXXXXXXX`。
# 実機・TestFlight 向けのアーカイブは Xcode の自動署名で（README）。

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

.PHONY: generate sim shots icon clean

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

icon:
	swift scripts/gen-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

clean:
	rm -rf build build-sim build-check $(PROJECT)
