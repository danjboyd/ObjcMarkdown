include $(GNUSTEP_MAKEFILES)/common.make

# libOpenSave gives Windows its native dialogs; elsewhere the theme does.
OMD_OPENSAVE_SUBPROJECTS =
OMD_OPENSAVE_LIB_DIR =
ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
  OMD_OPENSAVE_SUBPROJECTS = third_party/libs-OpenSave/Source
  OMD_OPENSAVE_LIB_DIR = :$(CURDIR)/third_party/libs-OpenSave/Source/$(GNUSTEP_OBJ_DIR)
endif

SUBPROJECTS = $(OMD_OPENSAVE_SUBPROJECTS) third_party/TextViewVimKitBuild third_party/GPUpdaterCore third_party/GPUpdaterUI third_party/gp-update-helper ObjcMarkdown ObjcMarkdownViewer ObjcMarkdownTests
ifneq ($(OMD_SKIP_TESTS),)
  SUBPROJECTS := $(filter-out ObjcMarkdownTests,$(SUBPROJECTS))
endif

OMD_RUNTIME_LIB_DIRS = $(CURDIR)/ObjcMarkdown/$(GNUSTEP_OBJ_DIR)$(OMD_OPENSAVE_LIB_DIR):$(CURDIR)/third_party/TextViewVimKitBuild/$(GNUSTEP_OBJ_DIR):$(CURDIR)/third_party/GPUpdaterCore/$(GNUSTEP_OBJ_DIR):$(CURDIR)/third_party/GPUpdaterUI/$(GNUSTEP_OBJ_DIR)

# MinGW's sys/types.h declares mode_t (unsigned short) and sets _MODE_T_;
# libdispatch's os/generic_win_base.h declares it again as int unless
# _MODE_T_ (current headers) or HAVE_MODE_T (older ones) is set. Including
# sys/types.h first and setting HAVE_MODE_T keeps the CRT's declaration and
# skips dispatch's with either version. Don't define _MODE_T_ here: that
# also hides the CRT's mode_t, and dispatch/io.h then fails.
ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
  export ADDITIONAL_OBJCFLAGS += -include sys/types.h -DHAVE_MODE_T=1
  export ADDITIONAL_CFLAGS += -include sys/types.h -DHAVE_MODE_T=1
endif

include $(GNUSTEP_MAKEFILES)/aggregate.make

# On Windows, each successful build is copied for the Start-menu launcher
# (MarkdownViewer-dev.ps1), which runs the copy, so a running app doesn't
# lock the DLLs the next build relinks.
ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
after-all::
	@bash "$(CURDIR)/scripts/windows/snapshot-dev-build.sh" \
	  "$(CURDIR)/ObjcMarkdownViewer/MarkdownViewer.app" "$(OMD_RUNTIME_LIB_DIRS)"
endif

.PHONY: run
run: all
	. "$(GNUSTEP_MAKEFILES)/GNUstep.sh"; \
	case "$$(uname -s)" in \
		MINGW*|MSYS*|CYGWIN*) \
			PATH="$(OMD_RUNTIME_LIB_DIRS):$${PATH}"; \
			;; \
		*) \
			LD_LIBRARY_PATH="$(OMD_RUNTIME_LIB_DIRS):/usr/GNUstep/System/Library/Libraries$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"; \
			;; \
	esac; \
	openapp "$(CURDIR)/ObjcMarkdownViewer/MarkdownViewer.app" $(filter-out run,$(MAKECMDGOALS))
