APP_NAME := Scribe
APP_BUNDLE := $(APP_NAME).app
APP_ZIP := $(APP_NAME).zip
APP_DMG := $(APP_NAME).dmg
BUILD_DIR := $(shell swift build -c release --show-bin-path 2>/dev/null || echo .build/release)
VERSION ?=
# Override these to do a Developer ID build for notarization:
#   make release CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#                ENTITLEMENTS=Scribe.entitlements
CODESIGN_IDENTITY ?= -
ENTITLEMENTS ?=

CODESIGN_FLAGS := --force --sign "$(CODESIGN_IDENTITY)"
ifneq ($(CODESIGN_IDENTITY),-)
  CODESIGN_FLAGS += --options runtime --timestamp
endif

# Inner code (frameworks, helpers) gets the same hardening but no app
# entitlements — Sparkle and its helpers ship with their own entitlements
# baked into Info.plists, and granting them ours would over-permission them.
CODESIGN_INNER_FLAGS := $(CODESIGN_FLAGS)

ifneq ($(strip $(ENTITLEMENTS)),)
  CODESIGN_FLAGS += --entitlements "$(ENTITLEMENTS)"
endif

.PHONY: build clean install run release dmg

build:
	swift build -c release
	$(eval BUILD_DIR := $(shell swift build -c release --show-bin-path))
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	mkdir -p $(APP_BUNDLE)/Contents/Frameworks
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Info.plist $(APP_BUNDLE)/Contents/
	cp AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@for b in $(BUILD_DIR)/*.bundle; do \
		[ -e "$$b" ] && cp -R "$$b" $(APP_BUNDLE)/Contents/Resources/ || true ; \
	done
	@for fw in $(BUILD_DIR)/*.framework; do \
		[ -d "$$fw" ] || continue; \
		name=$$(basename "$$fw"); \
		cp -R "$$fw" $(APP_BUNDLE)/Contents/Frameworks/ ; \
		echo "📦 Embedded $$name" ; \
	done
	@if [ -n "$(VERSION)" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist ; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist ; \
		echo "📌 Stamped version $(VERSION) into Info.plist" ; \
	fi
	@if [ -d "$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework" ]; then \
		SF=$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework ; \
		for x in "$$SF/Versions/B/XPCServices"/*.xpc ; do \
			[ -e "$$x" ] && codesign $(CODESIGN_INNER_FLAGS) "$$x" ; \
		done ; \
		codesign $(CODESIGN_INNER_FLAGS) "$$SF/Versions/B/Updater.app" ; \
		codesign $(CODESIGN_INNER_FLAGS) "$$SF/Versions/B/Autoupdate" ; \
		codesign $(CODESIGN_INNER_FLAGS) "$$SF" ; \
		echo "🔏 Signed Sparkle.framework" ; \
	fi
	@# Sign every other embedded framework (e.g. llama.framework). Sparkle is
	@# already handled above; idempotent re-signs would still work but the
	@# Sparkle block has its own subcomponent traversal so leave it alone.
	@for fw in $(APP_BUNDLE)/Contents/Frameworks/*.framework; do \
		[ -d "$$fw" ] || continue; \
		case "$$fw" in *Sparkle.framework) continue ;; esac; \
		codesign $(CODESIGN_INNER_FLAGS) "$$fw" ; \
		echo "🔏 Signed $$(basename $$fw)" ; \
	done
	codesign $(CODESIGN_FLAGS) $(APP_BUNDLE)
	@echo "\n✅ Built $(APP_BUNDLE)"

run: build
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE) $(APP_ZIP) $(APP_DMG)

install: build
	rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/
	@echo "✅ Installed to /Applications/$(APP_BUNDLE)"

release: build
	rm -f $(APP_ZIP)
	ditto -c -k --keepParent $(APP_BUNDLE) $(APP_ZIP)
	@echo "✅ Packaged $(APP_ZIP) ($$(du -h $(APP_ZIP) | cut -f1))"

# Builds a styled DMG with an Applications shortcut so users can drag-and-drop
# install. Requires `brew install create-dmg`. Signs the DMG when CODESIGN_IDENTITY
# is a real Developer ID — the workflow notarizes & staples it after this step.
dmg: build
	@command -v create-dmg >/dev/null || { echo "create-dmg not installed. Run: brew install create-dmg"; exit 1; }
	rm -f $(APP_DMG)
	create-dmg \
		--volname "$(APP_NAME)" \
		--window-pos 200 120 \
		--window-size 600 360 \
		--icon-size 110 \
		--icon "$(APP_BUNDLE)" 165 180 \
		--app-drop-link 435 180 \
		--hide-extension "$(APP_BUNDLE)" \
		--no-internet-enable \
		--hdiutil-quiet \
		"$(APP_DMG)" "$(APP_BUNDLE)"
	@if [ "$(CODESIGN_IDENTITY)" != "-" ]; then \
		codesign --force --sign "$(CODESIGN_IDENTITY)" --timestamp "$(APP_DMG)" ; \
		echo "🔏 Signed $(APP_DMG)" ; \
	fi
	@echo "✅ Packaged $(APP_DMG) ($$(du -h $(APP_DMG) | cut -f1))"
