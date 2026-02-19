include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECTS = third_party/libs-OpenSave/Source third_party/TextViewVimKitBuild ObjcMarkdown ObjcMarkdownViewer ObjcMarkdownTests

include $(GNUSTEP_MAKEFILES)/aggregate.make

.PHONY: run
run: all
	. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh; \
	LD_LIBRARY_PATH="$(CURDIR)/ObjcMarkdown/obj:$(CURDIR)/third_party/libs-OpenSave/Source/obj:$(CURDIR)/third_party/TextViewVimKitBuild/obj:/usr/GNUstep/System/Library/Libraries$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	openapp "$(CURDIR)/ObjcMarkdownViewer/ObjcMarkdownViewer.app" $(filter-out run,$(MAKECMDGOALS))
