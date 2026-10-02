/* ObjcMarkdown: <cmark.h> resolves here instead of a system libcmark header.
   The vendored cmark-gfm defines the same functions with different node type
   numbers, so mixing the two headers breaks silently at run time. */
#ifndef OBJCMARKDOWN_CMARK_COMPAT_H
#define OBJCMARKDOWN_CMARK_COMPAT_H
#include "cmark-gfm.h"
#endif
