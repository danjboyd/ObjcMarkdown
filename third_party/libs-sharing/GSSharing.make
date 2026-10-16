# GSSharing.make: compiles the sharing code into an app (or a theme).
#
# In the app's GNUmakefile, after including common.make:
#
#   GSSHARING_DIR = path/to/libs-sharing
#   include $(GSSHARING_DIR)/GSSharing.make
#   MyApp_OBJC_FILES += $(GSSHARING_OBJC_FILES)
#   MyApp_RESOURCE_FILES += $(GSSHARING_RESOURCE_FILES)
#   ADDITIONAL_INCLUDE_DIRS += $(GSSHARING_INCLUDE_DIRS)
#   ADDITIONAL_OBJCFLAGS += $(GSSHARING_OBJCFLAGS)
#   ADDITIONAL_LDFLAGS += $(GSSHARING_LDFLAGS)
#
# The code installs itself when it loads (GSSharingInstall()). On Linux and
# the BSDs it talks to the desktop through GIO (portals, the file manager,
# the mail app): GSSHARING_OBJCFLAGS and GSSHARING_LDFLAGS carry it, from
# pkg-config gio-unix-2.0, when it is there.
#
# GSSHARING_DIR must be a relative path, and the += lines must come before
# application.make (or bundle.make) is included.

GSSHARING_DIR ?= .

GSSHARING_OBJC_FILES = \
  $(GSSHARING_DIR)/Source/GSSharingService.m \
  $(GSSHARING_DIR)/Source/GSSharingPickerPanel.m \
  $(GSSHARING_DIR)/Source/GSSharingNotice.m \
  $(GSSHARING_DIR)/Source/GSSharingBuiltins.m \
  $(GSSHARING_DIR)/Source/GSSharingToolbarItem.m

GSSHARING_RESOURCE_FILES = $(wildcard $(GSSHARING_DIR)/Resources/*-symbolic.png)

GSSHARING_INCLUDE_DIRS = -I$(GSSHARING_DIR)/Headers -I$(GSSHARING_DIR)/Source

GSSHARING_OBJCFLAGS =
GSSHARING_LDFLAGS =
ifeq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
ifneq (,$(shell pkg-config --exists gio-unix-2.0 && echo yes))
GSSHARING_OBJCFLAGS += -DGSSHARING_HAVE_GIO $(shell pkg-config --cflags gio-unix-2.0)
GSSHARING_LDFLAGS += $(shell pkg-config --libs gio-unix-2.0)
endif
endif
