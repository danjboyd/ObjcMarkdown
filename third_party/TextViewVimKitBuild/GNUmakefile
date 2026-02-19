include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = TextViewVimKit

TextViewVimKit_OBJC_FILES = \
	../TextViewVimKit/src/GSVVimMode.m \
	../TextViewVimKit/src/GSVVimConfig.m \
	../TextViewVimKit/src/GSVVimConfigLoader.m \
	../TextViewVimKit/src/GSVTextViewAdapter.m \
	../TextViewVimKit/src/GSVVimEngine.m \
	../TextViewVimKit/src/GSVVimBindingController.m

TextViewVimKit_HEADER_FILES = \
	../TextViewVimKit/src/GSVVimMode.h \
	../TextViewVimKit/src/GSVVimConfig.h \
	../TextViewVimKit/src/GSVVimConfigLoader.h \
	../TextViewVimKit/src/GSVTextViewAdapter.h \
	../TextViewVimKit/src/GSVVimEngine.h \
	../TextViewVimKit/src/GSVVimBindingController.h

TextViewVimKit_CPPFLAGS += -I../TextViewVimKit/src
TextViewVimKit_LIBRARIES_DEPEND_UPON += -lgnustep-gui -lgnustep-base
ADDITIONAL_OBJCFLAGS += -fobjc-arc

include $(GNUSTEP_MAKEFILES)/library.make
