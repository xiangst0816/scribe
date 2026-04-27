APP_NAME := Scribe
APP_BUNDLE := $(APP_NAME).app
APP_ZIP := $(APP_NAME).zip
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
ifneq ($(strip $(ENTITLEMENTS)),)
  CODESIGN_FLAGS += --entitlements "$(ENTITLEMENTS)"
endif

.PHONY: build clean install run release

build:
	swift build -c release
	$(eval BUILD_DIR := $(shell swift build -c release --show-bin-path))
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Info.plist $(APP_BUNDLE)/Contents/
	cp AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@for b in $(BUILD_DIR)/*.bundle; do \
		[ -e "$$b" ] && cp -R "$$b" $(APP_BUNDLE)/Contents/Resources/ ; \
	done
	@if [ -n "$(VERSION)" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist ; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist ; \
		echo "📌 Stamped version $(VERSION) into Info.plist" ; \
	fi
	codesign $(CODESIGN_FLAGS) $(APP_BUNDLE)
	@echo "\n✅ Built $(APP_BUNDLE)"

run: build
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE) $(APP_ZIP)

install: build
	rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/
	@echo "✅ Installed to /Applications/$(APP_BUNDLE)"

release: build
	rm -f $(APP_ZIP)
	ditto -c -k --keepParent $(APP_BUNDLE) $(APP_ZIP)
	@echo "✅ Packaged $(APP_ZIP) ($$(du -h $(APP_ZIP) | cut -f1))"
