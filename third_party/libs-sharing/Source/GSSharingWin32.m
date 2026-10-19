/* GSSharingWin32.m: the Windows side of the built-in services: the
   clipboard as other Windows apps read it, Simple MAPI for email, and
   Explorer with the file selected.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharingPrivate.h"

#if !defined(GS_HAS_SHARING_SERVICES) && defined(_WIN32)

#include <windows.h>
/* shlobj.h brings in COM headers that declare with the interface macro,
   which GNUstep's headers undefine (it would turn @interface into
   @struct). Defined only around the include. */
#if !defined(interface)
#  define interface struct
#  define GSSHARING_UNDEF_INTERFACE
#endif
#include <shlobj.h>
#if defined(GSSHARING_UNDEF_INTERFACE)
#  undef interface
#  undef GSSHARING_UNDEF_INTERFACE
#endif

/* The clipboard.  GNUstep's win32 pasteboard server (libs-back's
   win32pbs) hands Windows only text and images, so files and RTF never
   reached Explorer, Outlook or Word.  These write the clipboard itself.
   The GNUstep pasteboard isn't declared as well: the server would empty
   the clipboard as it took it over; it still offers the text to GNUstep
   apps from the clipboard. */

static BOOL
GSSharingWin32Put(UINT format, const void *bytes, size_t length)
{
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, length);
  void *target;

  if (memory == NULL)
    {
      return NO;
    }
  target = GlobalLock(memory);
  if (target == NULL)
    {
      GlobalFree(memory);
      return NO;
    }
  memcpy(target, bytes, length);
  GlobalUnlock(memory);
  if (SetClipboardData(format, memory) == NULL)
    {
      GlobalFree(memory);
      return NO;
    }
  return YES;
}

static BOOL
GSSharingWin32PutText(NSString *text)
{
  NSUInteger length = [text length];
  unichar *characters = malloc((length + 1) * sizeof(unichar));
  BOOL put;

  if (characters == NULL)
    {
      return NO;
    }
  [text getCharacters: characters range: NSMakeRange(0, length)];
  characters[length] = 0;
  put = GSSharingWin32Put(CF_UNICODETEXT, characters,
                          (length + 1) * sizeof(unichar));
  free(characters);
  return put;
}

/* Another app may hold the clipboard for a moment. */
static BOOL
GSSharingWin32OpenClipboard(void)
{
  int attempt;

  for (attempt = 0; attempt < 10; attempt++)
    {
      if (OpenClipboard(NULL))
        {
          return YES;
        }
      Sleep(20);
    }
  return NO;
}

BOOL
GSSharingWin32WriteText(NSString *plain, NSData *rtf)
{
  BOOL wrote = NO;

  if (GSSharingWin32OpenClipboard() == NO)
    {
      return NO;
    }
  EmptyClipboard();
  if ([rtf length] > 0)
    {
      UINT format = RegisterClipboardFormatW(L"Rich Text Format");
      NSMutableData *terminated = [NSMutableData dataWithData: rtf];
      char nul = 0;

      [terminated appendBytes: &nul length: 1];
      if (format != 0
        && GSSharingWin32Put(format, [terminated bytes], [terminated length]))
        {
          wrote = YES;
        }
    }
  if (plain != nil && GSSharingWin32PutText(plain))
    {
      wrote = YES;
    }
  CloseClipboard();
  return wrote;
}

BOOL
GSSharingWin32WriteFiles(NSArray *paths, NSData *png)
{
  NSMutableData *drop;
  NSMutableString *text = [NSMutableString string];
  NSEnumerator *e = [paths objectEnumerator];
  NSString *path;
  DROPFILES *header;
  unichar nul = 0;
  BOOL wrote;

  if ([paths count] == 0)
    {
      return NO;
    }
  /* DROPFILES, each path as a NUL-terminated wide string, one more NUL. */
  drop = [NSMutableData dataWithLength: sizeof(DROPFILES)];
  header = (DROPFILES *)[drop mutableBytes];
  header->pFiles = sizeof(DROPFILES);
  header->fWide = TRUE;
  while ((path = [e nextObject]) != nil)
    {
      NSString *windowsPath = [path stringByReplacingOccurrencesOfString: @"/"
                                                               withString: @"\\"];
      NSUInteger length = [windowsPath length];
      unichar *characters = malloc((length + 1) * sizeof(unichar));

      if (characters == NULL)
        {
          return NO;
        }
      [windowsPath getCharacters: characters range: NSMakeRange(0, length)];
      characters[length] = 0;
      [drop appendBytes: characters length: (length + 1) * sizeof(unichar)];
      free(characters);
      if ([text length] > 0)
        {
          [text appendString: @"\r\n"];
        }
      [text appendString: windowsPath];
    }
  [drop appendBytes: &nul length: sizeof(nul)];

  if (GSSharingWin32OpenClipboard() == NO)
    {
      return NO;
    }
  EmptyClipboard();
  wrote = GSSharingWin32Put(CF_HDROP, [drop bytes], [drop length]);
  if (wrote)
    {
      /* Copy, not move: Explorer pastes a copy and leaves the file. */
      UINT format = RegisterClipboardFormatW(L"Preferred DropEffect");
      DWORD effect = DROPEFFECT_COPY;

      if (format != 0)
        {
          GSSharingWin32Put(format, &effect, sizeof(effect));
        }
      /* A picture file as its picture too, for chats and documents. */
      if ([png length] > 0)
        {
          UINT pngFormat = RegisterClipboardFormatW(L"PNG");

          if (pngFormat != 0)
            {
              GSSharingWin32Put(pngFormat, [png bytes], [png length]);
            }
        }
      GSSharingWin32PutText(text);
    }
  CloseClipboard();
  return wrote;
}

/* Explorer with the file selected. */
BOOL
GSSharingWin32ShowInFolder(NSString *path)
{
  NSString *windowsPath = [path stringByReplacingOccurrencesOfString: @"/"
                                                           withString: @"\\"];
  NSUInteger length = [windowsPath length];
  unichar *characters = malloc((length + 1) * sizeof(unichar));
  PIDLIST_ABSOLUTE list;
  HRESULT result = E_FAIL;

  if (characters == NULL)
    {
      return NO;
    }
  [windowsPath getCharacters: characters range: NSMakeRange(0, length)];
  characters[length] = 0;
  list = ILCreateFromPathW((const wchar_t *)characters);
  free(characters);
  if (list != NULL)
    {
      CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
      result = SHOpenFolderAndSelectItems(list, 0, NULL, 0);
      ILFree(list);
    }
  return SUCCEEDED(result);
}

/* Email through Simple MAPI's wide API (Windows 8 and later), which
   MinGW-w64's mapi.h doesn't declare; the layouts are the Windows SDK's. */
typedef struct
{
  ULONG ulReserved;
  ULONG ulRecipClass;
  PWSTR lpszName;
  PWSTR lpszAddress;
  ULONG ulEIDSize;
  PVOID lpEntryID;
} GSSharingMapiRecipDescW;

typedef struct
{
  ULONG ulReserved;
  ULONG flFlags;
  ULONG nPosition;
  PWSTR lpszPathName;
  PWSTR lpszFileName;
  PVOID lpFileType;
} GSSharingMapiFileDescW;

typedef struct
{
  ULONG ulReserved;
  PWSTR lpszSubject;
  PWSTR lpszNoteText;
  PWSTR lpszMessageType;
  PWSTR lpszDateReceived;
  PWSTR lpszConversationID;
  ULONG flFlags;
  GSSharingMapiRecipDescW *lpOriginator;
  ULONG nRecipCount;
  GSSharingMapiRecipDescW *lpRecips;
  ULONG nFileCount;
  GSSharingMapiFileDescW *lpFiles;
} GSSharingMapiMessageW;

typedef ULONG (WINAPI *GSSharingMAPISendMailW)(ULONG_PTR session,
  ULONG_PTR uiParam, GSSharingMapiMessageW *message, ULONG flags,
  ULONG reserved);

#define GSSHARING_MAPI_LOGON_UI 0x00000001
#define GSSHARING_MAPI_DIALOG 0x00000008
#define GSSHARING_MAPI_USER_ABORT 1
#define GSSHARING_MAPI_TO 1

/* Whether the default mail client takes Simple MAPI: Clients\Mail names
   it (the user's choice first) and its key names its MAPI DLL. The new
   Outlook, webmail and "none" don't; mapi32.dll would then show its own
   "no email program" message and report a cancel. */
BOOL
GSSharingWin32MailClientTakesMAPI(void)
{
  static const wchar_t *clients = L"Software\\Clients\\Mail";
  static const wchar_t *values[] = { L"DLLPathEx", L"DLLPath" };
  wchar_t client[256];
  wchar_t key[300];
  DWORD size = sizeof(client);
  unsigned i;

  if (RegGetValueW(HKEY_CURRENT_USER, clients, NULL, RRF_RT_REG_SZ, NULL,
                   client, &size) != ERROR_SUCCESS || client[0] == 0)
    {
      size = sizeof(client);
      if (RegGetValueW(HKEY_LOCAL_MACHINE, clients, NULL, RRF_RT_REG_SZ, NULL,
                       client, &size) != ERROR_SUCCESS || client[0] == 0)
        {
          return NO;
        }
    }
  _snwprintf(key, sizeof(key) / sizeof(key[0]), L"%ls\\%ls", clients, client);
  key[sizeof(key) / sizeof(key[0]) - 1] = 0;
  for (i = 0; i < 2; i++)
    {
      wchar_t dll[MAX_PATH];

      size = sizeof(dll);
      if (RegGetValueW(HKEY_LOCAL_MACHINE, key, values[i],
                       RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND,
                       NULL, dll, &size) == ERROR_SUCCESS && dll[0] != 0)
        {
          return YES;
        }
    }
  return NO;
}

/* A NUL-terminated UTF-16 copy, valid until the autorelease pool drains. */
static PWSTR
GSSharingWin32Wide(NSString *string)
{
  NSMutableData *data;
  unichar nul = 0;

  if (string == nil)
    {
      return NULL;
    }
  data = [NSMutableData dataWithData:
    [string dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  [data appendBytes: &nul length: sizeof(nul)];
  return (PWSTR)[data bytes];
}

/* A draft in the MAPI client with the files attached. Blocks until the
   client is done with it (some clients until the compose window closes),
   so callers run it off the main thread. YES when the draft opened or
   the user cancelled it in the client. */
BOOL
GSSharingWin32SendMail(NSString *subject, NSArray *paths,
                       NSArray *recipients, void *window)
{
  CREATE_AUTORELEASE_POOL(pool);
  HMODULE mapi;
  GSSharingMAPISendMailW send;
  GSSharingMapiFileDescW *files;
  GSSharingMapiRecipDescW *to = NULL;
  GSSharingMapiMessageW message;
  NSUInteger i;
  ULONG status = (ULONG)-1;

  OleInitialize(NULL);
  mapi = LoadLibraryW(L"mapi32.dll");
  send = mapi != NULL
    ? (GSSharingMAPISendMailW)(void *)GetProcAddress(mapi, "MAPISendMailW")
    : NULL;
  if (send != NULL)
    {
      files = calloc([paths count] > 0 ? [paths count] : 1,
                     sizeof(GSSharingMapiFileDescW));
      if ([recipients count] > 0)
        {
          to = calloc([recipients count], sizeof(GSSharingMapiRecipDescW));
        }
      if (files != NULL && ([recipients count] == 0 || to != NULL))
        {
          for (i = 0; i < [paths count]; i++)
            {
              NSString *path = [[paths objectAtIndex: i]
                stringByReplacingOccurrencesOfString: @"/" withString: @"\\"];

              files[i].nPosition = (ULONG)-1;
              files[i].lpszPathName = GSSharingWin32Wide(path);
              files[i].lpszFileName = GSSharingWin32Wide([path lastPathComponent]);
            }
          for (i = 0; i < [recipients count]; i++)
            {
              NSString *address = [NSString stringWithFormat: @"SMTP:%@",
                                            [recipients objectAtIndex: i]];

              to[i].ulRecipClass = GSSHARING_MAPI_TO;
              to[i].lpszName = GSSharingWin32Wide([recipients objectAtIndex: i]);
              to[i].lpszAddress = GSSharingWin32Wide(address);
            }
          memset(&message, 0, sizeof(message));
          message.lpszSubject = GSSharingWin32Wide(subject);
          message.nFileCount = (ULONG)[paths count];
          message.lpFiles = [paths count] > 0 ? files : NULL;
          message.nRecipCount = (ULONG)[recipients count];
          message.lpRecips = to;
          status = send(0, (ULONG_PTR)window, &message,
                        GSSHARING_MAPI_LOGON_UI | GSSHARING_MAPI_DIALOG, 0);
        }
      free(files);
      free(to);
    }
  if (mapi != NULL)
    {
      FreeLibrary(mapi);
    }
  OleUninitialize();
  RELEASE(pool);
  return status == 0 || status == GSSHARING_MAPI_USER_ABORT;
}

#endif /* !GS_HAS_SHARING_SERVICES && _WIN32 */
