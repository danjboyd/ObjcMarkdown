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

ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
  export ADDITIONAL_OBJCFLAGS += -include sys/types.h -D__mode_t_defined -D_MODE_T_ -D_MODE_T_DEFINED
  export ADDITIONAL_CFLAGS += -include sys/types.h -D__mode_t_defined -D_MODE_T_ -D_MODE_T_DEFINED
endif

include $(GNUSTEP_MAKEFILES)/aggregate.make

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
