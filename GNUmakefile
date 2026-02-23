include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECTS = third_party/libs-OpenSave/Source third_party/TextViewVimKitBuild ObjcMarkdown ObjcMarkdownViewer ObjcMarkdownTests
ifneq ($(OMD_SKIP_TESTS),)
  SUBPROJECTS := $(filter-out ObjcMarkdownTests,$(SUBPROJECTS))
endif

include $(GNUSTEP_MAKEFILES)/aggregate.make

OMD_RUNTIME_LIB_DIRS = $(CURDIR)/ObjcMarkdown/$(GNUSTEP_OBJ_DIR):$(CURDIR)/third_party/libs-OpenSave/Source/$(GNUSTEP_OBJ_DIR):$(CURDIR)/third_party/TextViewVimKitBuild/$(GNUSTEP_OBJ_DIR)

ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
  export ADDITIONAL_OBJCFLAGS += -D__mode_t_defined -D_MODE_T_ -D_MODE_T_DEFINED
  export ADDITIONAL_CFLAGS += -D__mode_t_defined -D_MODE_T_ -D_MODE_T_DEFINED
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
