# macOS build: the library, the viewer as MarkdownViewer.app and the XCTest
# bundle, with Apple's clang and the Cocoa frameworks (no GNUstep).
#
#   make -C macos            # build/MarkdownViewer.app (universal)
#   make -C macos test       # build and run the tests
#   make -C macos run        # build and open the app
#   make -C macos ARCHS=arm64   # one architecture only (faster)
#   make -C macos dmg        # build/MarkdownViewer-<version>-macos.dmg
#
# Source lists are read from the GNUstep makefiles, so a file added there is
# built here too.

ROOT := $(abspath ..)
BUILD := $(abspath build)

# The version, as the GNUstep build takes it: VERSION at the top, or
# OMD_VERSION=0.1.2-rc1. Info.plist's CFBundleShortVersionString takes only
# its numbers ("0.1.2"); About shows all of it.
OMD_VERSION ?= $(strip $(shell cat $(ROOT)/VERSION 2>/dev/null))
SHORT_VERSION := $(shell echo '$(OMD_VERSION)' | sed -E 's/^([0-9]+(\.[0-9]+)*).*/\1/')
BUILD_NUMBER ?= 1
ARCHS ?= arm64 x86_64
# Objects per set of architectures, so ARCHS=arm64 and a universal build
# don't mix.
empty :=
space := $(empty) $(empty)
OBJDIR := $(BUILD)/obj-$(subst $(space),-,$(strip $(ARCHS)))
MACOSX_DEPLOYMENT_TARGET ?= 11.0

CC := xcrun clang
PLATFORM_DIR := $(shell xcrun --show-sdk-platform-path)
ARCH_FLAGS := $(foreach a,$(ARCHS),-arch $(a)) -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)
COMMON_FLAGS := $(ARCH_FLAGS) -g -O2 -Wall -Wno-deprecated-declarations
ifneq ($(OMD_WERROR),)
WERROR := -Werror
endif
# make V=1 shows the commands.
ifeq ($(V),1)
Q :=
else
Q := @
endif

CMARK_DIR := $(ROOT)/third_party/cmark-gfm
CMARK_CPPFLAGS := -I$(CMARK_DIR)/compat -I$(CMARK_DIR)/src -I$(CMARK_DIR)/extensions -DCMARK_GFM_STATIC_DEFINE
VIM_DIR := $(ROOT)/third_party/TextViewVimKit/src

gnustep_list = $(shell sed -n 's/^$(2) *= *//p' $(ROOT)/$(1))

LIB_OBJC := $(addprefix ObjcMarkdown/,$(call gnustep_list,ObjcMarkdown/GNUmakefile,ObjcMarkdown_OBJC_FILES))
LIB_C := $(patsubst $(ROOT)/%,%,$(wildcard $(CMARK_DIR)/src/*.c) $(wildcard $(CMARK_DIR)/extensions/*.c)) third_party/tomlc99/toml.c
VIM_OBJC := $(patsubst $(ROOT)/%,%,$(wildcard $(VIM_DIR)/*.m))
APP_OBJC := $(addprefix ObjcMarkdownViewer/,$(call gnustep_list,ObjcMarkdownViewer/GNUmakefile,MarkdownViewer_OBJC_FILES))
TEST_OBJC := $(patsubst ObjcMarkdownTests/../%,%,$(addprefix ObjcMarkdownTests/,$(call gnustep_list,ObjcMarkdownTests/GNUmakefile,ObjcMarkdownTests_OBJC_FILES)))

obj = $(addprefix $(OBJDIR)/$(1)/,$(addsuffix .o,$(2)))
LIB_OBJS := $(call obj,lib,$(LIB_OBJC) $(LIB_C))
VIM_OBJS := $(call obj,vim,$(VIM_OBJC))
APP_OBJS := $(call obj,app,$(APP_OBJC))
TEST_OBJS := $(call obj,test,$(TEST_OBJC))
# The Quick Look preview extension: its controller and the app's preview view.
QL_OBJC := macos/QuickLook/OMDQuickLookPreviewController.m ObjcMarkdownViewer/OMDTextView.m ObjcMarkdownViewer/OMDTextFileSupport.m
QL_OBJS := $(call obj,ql,$(QL_OBJC))

LIB_FLAGS := $(COMMON_FLAGS) -I$(ROOT)/ObjcMarkdown $(CMARK_CPPFLAGS) -I$(ROOT)/third_party/tomlc99 -DOBJCMARKDOWN_ENABLE_TOML_THEME=1
VIM_FLAGS := $(COMMON_FLAGS) -fobjc-arc -I$(VIM_DIR)
APP_FLAGS := $(COMMON_FLAGS) $(WERROR) -DOMD_APP_VERSION=\"$(OMD_VERSION)\" -I$(ROOT)/ObjcMarkdown -I$(ROOT)/ObjcMarkdownViewer $(CMARK_CPPFLAGS) -I$(VIM_DIR)
QL_FLAGS := $(APP_FLAGS) -fapplication-extension
TEST_FLAGS := $(APP_FLAGS) -F$(PLATFORM_DIR)/Developer/Library/Frameworks -DOM_SPEC_DIR=\"$(ROOT)/ObjcMarkdownTests/Spec\"

LIB := $(BUILD)/libObjcMarkdown.a
VIM_LIB := $(BUILD)/libTextViewVimKit.a
APP := $(BUILD)/MarkdownViewer.app
TESTS := $(BUILD)/ObjcMarkdownTests.xctest
APPEX := $(BUILD)/MarkdownPreview.appex
DMG := $(BUILD)/MarkdownViewer-$(OMD_VERSION)-macos.dmg

APP_RESOURCES := $(ROOT)/Resources/theme-github.toml $(ROOT)/Resources/theme-github-dark.toml \
	$(ROOT)/Resources/markdown_icon.png $(wildcard $(ROOT)/Resources/icons/*-symbolic.png)

.PHONY: all app dmg test run clean
all: app
app: $(APP)

$(OBJDIR)/lib/%.c.o: $(ROOT)/%.c
	@mkdir -p $(dir $@)
	@echo "  CC $(patsubst $(ROOT)/%,%,$<)"
	$(Q)$(CC) $(LIB_FLAGS) -std=c99 -MMD -MP -c $< -o $@
$(OBJDIR)/lib/%.m.o: $(ROOT)/%.m
	@mkdir -p $(dir $@)
	@echo "  CC $(patsubst $(ROOT)/%,%,$<)"
	$(Q)$(CC) $(LIB_FLAGS) $(WERROR) -MMD -MP -c $< -o $@
$(OBJDIR)/vim/%.m.o: $(ROOT)/%.m
	@mkdir -p $(dir $@)
	@echo "  CC $(patsubst $(ROOT)/%,%,$<)"
	$(Q)$(CC) $(VIM_FLAGS) -MMD -MP -c $< -o $@
$(OBJDIR)/app/%.m.o: $(ROOT)/%.m
	@mkdir -p $(dir $@)
	@echo "  CC $(patsubst $(ROOT)/%,%,$<)"
	$(Q)$(CC) $(APP_FLAGS) -MMD -MP -c $< -o $@
$(OBJDIR)/ql/%.m.o: $(ROOT)/%.m
	@mkdir -p $(dir $@)
	@echo "  CC $(patsubst $(ROOT)/%,%,$<)"
	$(Q)$(CC) $(QL_FLAGS) -MMD -MP -c $< -o $@
$(OBJDIR)/test/%.m.o: $(ROOT)/%.m
	@mkdir -p $(dir $@)
	@echo "  CC $(patsubst $(ROOT)/%,%,$<)"
	$(Q)$(CC) $(TEST_FLAGS) -MMD -MP -c $< -o $@

$(LIB): $(LIB_OBJS)
	@rm -f $@
	@echo "  AR $(notdir $@)"
	$(Q)xcrun libtool -static -o $@ $^
$(VIM_LIB): $(VIM_OBJS)
	@rm -f $@
	@echo "  AR $(notdir $@)"
	$(Q)xcrun libtool -static -o $@ $^

FRAMEWORKS := -framework Cocoa

# Sandboxed, as app extensions must be; the system finds it in the app's
# PlugIns folder.
$(APPEX): $(QL_OBJS) $(LIB) QuickLook/Info.plist QuickLook/QuickLook.entitlements
	@rm -rf $@
	@mkdir -p $@/Contents/MacOS
	@echo "  LD $(notdir $@)"
	$(Q)$(CC) $(ARCH_FLAGS) -fapplication-extension -e _NSExtensionMain -o $@/Contents/MacOS/MarkdownPreview \
		$(QL_OBJS) $(LIB) $(FRAMEWORKS) -framework Quartz
	$(Q)sed -e 's/@VERSION@/$(SHORT_VERSION)/g' -e 's/@BUILD_NUMBER@/$(BUILD_NUMBER)/g' QuickLook/Info.plist > $@/Contents/Info.plist
	$(Q)plutil -lint -s $@/Contents/Info.plist
	$(Q)codesign --force --sign - --entitlements QuickLook/QuickLook.entitlements $@

$(APP): $(APP_OBJS) $(LIB) $(VIM_LIB) Info.plist $(APP_RESOURCES) $(BUILD)/MarkdownViewer.icns $(APPEX)
	@rm -rf $@
	@mkdir -p $@/Contents/MacOS $@/Contents/Resources
	@echo "  LD $(notdir $@)"
	$(Q)$(CC) $(ARCH_FLAGS) -o $@/Contents/MacOS/MarkdownViewer $(APP_OBJS) $(LIB) $(VIM_LIB) $(FRAMEWORKS)
	$(Q)sed -e 's/@VERSION@/$(SHORT_VERSION)/g' -e 's/@BUILD_NUMBER@/$(BUILD_NUMBER)/g' Info.plist > $@/Contents/Info.plist
	$(Q)plutil -lint -s $@/Contents/Info.plist
	$(Q)printf 'APPL????' > $@/Contents/PkgInfo
	$(Q)cp $(APP_RESOURCES) $(BUILD)/MarkdownViewer.icns $@/Contents/Resources/
	@mkdir -p $@/Contents/PlugIns
	$(Q)cp -R $(APPEX) $@/Contents/PlugIns/
	$(Q)codesign --force --sign - $@

# The app icon from Resources/markdown_icon.png.
$(BUILD)/MarkdownViewer.icns: $(ROOT)/Resources/markdown_icon.png
	@rm -rf $(BUILD)/MarkdownViewer.iconset
	@mkdir -p $(BUILD)/MarkdownViewer.iconset
	@for s in 16 32 128 256 512; do \
		sips -z $$s $$s $< --out $(BUILD)/MarkdownViewer.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s * 2)); \
		sips -z $$d $$d $< --out $(BUILD)/MarkdownViewer.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	$(Q)iconutil -c icns -o $@ $(BUILD)/MarkdownViewer.iconset

# XCTest itself needs macOS 14, so the bundle does too.
$(TESTS): $(TEST_OBJS) $(LIB)
	@rm -rf $@
	@mkdir -p $@/Contents/MacOS
	@echo "  LD $(notdir $@)"
	$(Q)$(CC) $(ARCH_FLAGS) -mmacosx-version-min=14.0 -bundle -o $@/Contents/MacOS/ObjcMarkdownTests $(TEST_OBJS) $(LIB) \
		$(FRAMEWORKS) -F$(PLATFORM_DIR)/Developer/Library/Frameworks -framework XCTest \
		-Wl,-rpath,$(PLATFORM_DIR)/Developer/Library/Frameworks
	$(Q)sed -e 's/@VERSION@/$(SHORT_VERSION)/g' TestsInfo.plist > $@/Contents/Info.plist
	$(Q)codesign --force --sign - $@

# A disk image with the app and a link to Applications to drag it to.
dmg: $(DMG)
$(DMG): $(APP)
	@echo "  DMG $(notdir $@)"
	@rm -rf $(BUILD)/dmg $@
	@mkdir -p $(BUILD)/dmg
	$(Q)cp -R $(APP) $(BUILD)/dmg/
	$(Q)ln -s /Applications $(BUILD)/dmg/Applications
	$(Q)hdiutil create -quiet -volname "MarkdownViewer $(OMD_VERSION)" -srcfolder $(BUILD)/dmg \
		-format UDZO -imagekey zlib-level=9 -fs HFS+ $@
	@rm -rf $(BUILD)/dmg

test: $(TESTS)
	xcrun xctest $(TESTS)

run: $(APP)
	open $(APP)

clean:
	rm -rf $(BUILD)

-include $(shell find $(OBJDIR) -name '*.d' 2>/dev/null)
