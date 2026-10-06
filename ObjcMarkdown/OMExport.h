// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef OM_EXPORT_H
#define OM_EXPORT_H

// OM_EXPORT declares a constant or function that ObjcMarkdown exports.
// FOUNDATION_EXPORT is gnustep-base's macro and means dllimport outside
// gnustep-base, so on Windows the library would import its own symbols
// and the linker would leave them out of ObjcMarkdown-0.dll. gnustep-make
// defines BUILD_libObjcMarkdown_DLL while it builds this library.
#if defined(_WIN32) && defined(GNUSTEP_WITH_DLL)
#  if defined(BUILD_libObjcMarkdown_DLL)
#    define OM_EXPORT_ATTRIBUTE __declspec(dllexport)
#  else
#    define OM_EXPORT_ATTRIBUTE __declspec(dllimport)
#  endif
#else
#  define OM_EXPORT_ATTRIBUTE
#endif

#if defined(__cplusplus)
#  define OM_EXPORT extern "C" OM_EXPORT_ATTRIBUTE
#else
#  define OM_EXPORT extern OM_EXPORT_ATTRIBUTE
#endif

#endif
