@echo off
setlocal

set "ROOT=%~dp0"
set "MSYS2_ROOT=C:\msys64"
set "ENV_EXE=%MSYS2_ROOT%\usr\bin\env.exe"

if not exist "%ENV_EXE%" (
  echo MSYS2 env.exe not found at "%ENV_EXE%".
  echo Update MarkdownViewer-dev.cmd if your MSYS2 install lives elsewhere.
  exit /b 1
)

"%ENV_EXE%" MSYSTEM=CLANG64 CHERE_INVOKING=1 /usr/bin/bash -lc ^
  "source /etc/profile; cd '/c/Users/Support/git/ObjcMarkdown'; exec ./scripts/omd-viewer-msys2.sh"

exit /b %ERRORLEVEL%
