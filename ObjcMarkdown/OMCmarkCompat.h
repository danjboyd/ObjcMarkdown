// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef OMD_CMARK_COMPAT_H
#define OMD_CMARK_COMPAT_H

#if __has_include(<cmark.h>)
#include <cmark.h>
#elif __has_include(<cmark/cmark.h>)
#include <cmark/cmark.h>
#else
#error "cmark headers not found"
#endif

#endif
