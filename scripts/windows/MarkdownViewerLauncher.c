#define UNICODE
#define _UNICODE

#include <windows.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <stdio.h>
#include <wchar.h>

#define OMD_MAX_PATH 32768

static void OMDShowError(const wchar_t *message)
{
    MessageBoxW(NULL, message, L"ObjcMarkdown", MB_OK | MB_ICONERROR);
}

static BOOL OMDFileExists(const wchar_t *path)
{
    DWORD attrs = GetFileAttributesW(path);
    return attrs != INVALID_FILE_ATTRIBUTES;
}

static BOOL OMDDirectoryExists(const wchar_t *path)
{
    DWORD attrs = GetFileAttributesW(path);
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

static BOOL OMDJoinPath(wchar_t *dest, size_t destCount, const wchar_t *left, const wchar_t *right);

static BOOL OMDThemeBundleExistsInDirectory(const wchar_t *themesRoot, const wchar_t *themeName)
{
    wchar_t themeDll[OMD_MAX_PATH];
    int written = 0;

    if (themesRoot == NULL || themeName == NULL) {
        return FALSE;
    }

    written = swprintf(themeDll,
                       OMD_MAX_PATH,
                       L"%ls\\%ls.theme\\%ls.dll",
                       themesRoot,
                       themeName,
                       themeName);
    if (written < 0 || written >= (int)OMD_MAX_PATH) {
        return FALSE;
    }

    return OMDFileExists(themeDll);
}

static const wchar_t *OMDPreferredThemeName(const wchar_t *runtimeRoot)
{
    wchar_t themesRoot[OMD_MAX_PATH];
    wchar_t userProfile[OMD_MAX_PATH];
    wchar_t userThemesRoot[OMD_MAX_PATH];
    DWORD userProfileLen = 0;

    if (runtimeRoot != NULL) {
        if (OMDJoinPath(themesRoot, OMD_MAX_PATH, runtimeRoot, L"lib\\GNUstep\\Themes") &&
            OMDThemeBundleExistsInDirectory(themesRoot, L"WinUITheme")) {
            return L"WinUITheme";
        }
    }

    userProfileLen = GetEnvironmentVariableW(L"USERPROFILE", userProfile, OMD_MAX_PATH);
    if (userProfileLen > 0 && userProfileLen < OMD_MAX_PATH) {
        int written = swprintf(userThemesRoot,
                               OMD_MAX_PATH,
                               L"%ls\\GNUstep\\Library\\Themes",
                               userProfile);
        if (written >= 0 && written < (int)OMD_MAX_PATH &&
            OMDThemeBundleExistsInDirectory(userThemesRoot, L"WinUITheme")) {
            return L"WinUITheme";
        }
    }

    return L"WinUXTheme";
}

static BOOL OMDJoinPath(wchar_t *dest, size_t destCount, const wchar_t *left, const wchar_t *right)
{
    int written = swprintf(dest, destCount, L"%ls\\%ls", left, right);
    return written >= 0 && (size_t)written < destCount;
}

static BOOL OMDQuoteArgument(wchar_t *dest, size_t destCount, const wchar_t *arg)
{
    size_t len = 0;

    if (destCount < 3) {
        return FALSE;
    }

    dest[len++] = L'"';
    while (*arg != L'\0') {
        unsigned backslashes = 0;
        while (*arg == L'\\') {
            backslashes++;
            arg++;
        }

        if (*arg == L'\0') {
            while (backslashes-- > 0) {
                if (len + 2 >= destCount) {
                    return FALSE;
                }
                dest[len++] = L'\\';
                dest[len++] = L'\\';
            }
            break;
        }

        if (*arg == L'"') {
            while (backslashes-- > 0) {
                if (len + 2 >= destCount) {
                    return FALSE;
                }
                dest[len++] = L'\\';
                dest[len++] = L'\\';
            }
            if (len + 2 >= destCount) {
                return FALSE;
            }
            dest[len++] = L'\\';
            dest[len++] = L'"';
            arg++;
            continue;
        }

        while (backslashes-- > 0) {
            if (len + 1 >= destCount) {
                return FALSE;
            }
            dest[len++] = L'\\';
        }
        if (len + 1 >= destCount) {
            return FALSE;
        }
        dest[len++] = *arg++;
    }

    if (len + 2 > destCount) {
        return FALSE;
    }
    dest[len++] = L'"';
    dest[len] = L'\0';
    return TRUE;
}

static BOOL OMDBuildChildCommandLine(wchar_t *dest, size_t destCount, const wchar_t *appPath)
{
    int argc = 0;
    int i = 0;
    size_t used = 0;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    wchar_t quotedArg[OMD_MAX_PATH];

    if (argv == NULL) {
        return FALSE;
    }

    if (!OMDQuoteArgument(quotedArg, OMD_MAX_PATH, appPath)) {
        LocalFree(argv);
        return FALSE;
    }

    used = wcslen(quotedArg);
    if (used + 1 > destCount) {
        LocalFree(argv);
        return FALSE;
    }
    wcscpy(dest, quotedArg);

    for (i = 1; i < argc; i++) {
        size_t quotedLen = 0;
        if (!OMDQuoteArgument(quotedArg, OMD_MAX_PATH, argv[i])) {
            LocalFree(argv);
            return FALSE;
        }
        quotedLen = wcslen(quotedArg);
        if (used + 1 + quotedLen + 1 > destCount) {
            LocalFree(argv);
            return FALSE;
        }
        dest[used++] = L' ';
        wcscpy(dest + used, quotedArg);
        used += quotedLen;
    }

    LocalFree(argv);
    return TRUE;
}

static BOOL OMDPrependPath(const wchar_t *binPath)
{
    DWORD currentLen = GetEnvironmentVariableW(L"PATH", NULL, 0);
    wchar_t *current = NULL;
    wchar_t *updated = NULL;
    size_t updatedCount = 0;
    BOOL ok = FALSE;

    if (currentLen == 0) {
        currentLen = 1;
    }

    current = (wchar_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, currentLen * sizeof(wchar_t));
    if (current == NULL) {
        return FALSE;
    }

    if (currentLen > 1) {
        GetEnvironmentVariableW(L"PATH", current, currentLen);
    } else {
        current[0] = L'\0';
    }

    updatedCount = wcslen(binPath) + 1 + wcslen(current) + 1;
    updated = (wchar_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, updatedCount * sizeof(wchar_t));
    if (updated == NULL) {
        HeapFree(GetProcessHeap(), 0, current);
        return FALSE;
    }

    swprintf(updated, updatedCount, L"%ls;%ls", binPath, current);
    ok = SetEnvironmentVariableW(L"PATH", updated);

    HeapFree(GetProcessHeap(), 0, updated);
    HeapFree(GetProcessHeap(), 0, current);
    return ok;
}

static BOOL OMDConfigureFontconfig(const wchar_t *runtimeRoot)
{
    wchar_t fontconfigPath[OMD_MAX_PATH];
    wchar_t fontconfigFile[OMD_MAX_PATH];

    if (!OMDJoinPath(fontconfigPath, OMD_MAX_PATH, runtimeRoot, L"etc\\fonts")) {
        return FALSE;
    }
    if (!OMDJoinPath(fontconfigFile, OMD_MAX_PATH, fontconfigPath, L"fonts.conf")) {
        return FALSE;
    }

    if (OMDFileExists(fontconfigFile)) {
        if (!SetEnvironmentVariableW(L"FONTCONFIG_PATH", fontconfigPath)) {
            return FALSE;
        }
        if (!SetEnvironmentVariableW(L"FONTCONFIG_FILE", fontconfigFile)) {
            return FALSE;
        }
    }

    return TRUE;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR commandLine, int showCommand)
{
    wchar_t launcherPath[OMD_MAX_PATH];
    wchar_t rootDir[OMD_MAX_PATH];
    wchar_t appPath[OMD_MAX_PATH];
    wchar_t localRuntimeRoot[OMD_MAX_PATH];
    wchar_t localRuntimeBin[OMD_MAX_PATH];
    wchar_t bundledTeXRoot[OMD_MAX_PATH];
    wchar_t bundledTeXBin[OMD_MAX_PATH];
    wchar_t runtimeRoot[OMD_MAX_PATH];
    wchar_t runtimeBin[OMD_MAX_PATH];
    wchar_t commandBuffer[OMD_MAX_PATH];
    wchar_t errorBuffer[OMD_MAX_PATH];
    STARTUPINFOW startupInfo;
    PROCESS_INFORMATION processInfo;
    DWORD pathLen = 0;

    (void)instance;
    (void)previous;
    (void)commandLine;
    (void)showCommand;

    pathLen = GetModuleFileNameW(NULL, launcherPath, OMD_MAX_PATH);
    if (pathLen == 0 || pathLen >= OMD_MAX_PATH) {
        OMDShowError(L"Unable to resolve the launcher location.");
        return 1;
    }

    wcscpy(rootDir, launcherPath);
    if (!PathRemoveFileSpecW(rootDir)) {
        OMDShowError(L"Unable to determine the installation directory.");
        return 1;
    }

    if (!OMDJoinPath(appPath, OMD_MAX_PATH, rootDir, L"app\\MarkdownViewer.app\\MarkdownViewer.exe")) {
        OMDShowError(L"Unable to construct the app path.");
        return 1;
    }
    if (!OMDFileExists(appPath)) {
        OMDShowError(L"MarkdownViewer.exe was not found inside the app bundle.");
        return 1;
    }

    if (!OMDJoinPath(localRuntimeRoot, OMD_MAX_PATH, rootDir, L"clang64") ||
        !OMDJoinPath(localRuntimeBin, OMD_MAX_PATH, localRuntimeRoot, L"bin")) {
        OMDShowError(L"Unable to construct the runtime path.");
        return 1;
    }

    if (OMDDirectoryExists(localRuntimeBin)) {
        wcscpy(runtimeRoot, localRuntimeRoot);
        wcscpy(runtimeBin, localRuntimeBin);
    } else if (OMDDirectoryExists(L"C:\\clang64\\bin")) {
        wcscpy(runtimeRoot, L"C:\\clang64");
        wcscpy(runtimeBin, L"C:\\clang64\\bin");
    } else {
        OMDShowError(L"GNUstep runtime files were not found.\n\nReinstall ObjcMarkdown or keep the bundled clang64 folder next to the launcher.");
        return 1;
    }

    if (!OMDPrependPath(runtimeBin)) {
        OMDShowError(L"Unable to configure the runtime search path.");
        return 1;
    }

    if (OMDJoinPath(bundledTeXRoot, OMD_MAX_PATH, runtimeRoot, L"texlive\\TinyTeX") &&
        OMDJoinPath(bundledTeXBin, OMD_MAX_PATH, bundledTeXRoot, L"bin\\windows") &&
        OMDDirectoryExists(bundledTeXBin)) {
        if (!OMDPrependPath(bundledTeXBin)) {
            OMDShowError(L"Unable to configure the bundled TinyTeX search path.");
            return 1;
        }
    }

    if (!SetEnvironmentVariableW(L"GNUSTEP_PATHPREFIX_LIST", runtimeRoot)) {
        OMDShowError(L"Unable to configure GNUstep runtime paths.");
        return 1;
    }

    if (!OMDConfigureFontconfig(runtimeRoot)) {
        OMDShowError(L"Unable to configure font runtime paths.");
        return 1;
    }

    if (GetEnvironmentVariableW(L"GSTheme", NULL, 0) == 0) {
        SetEnvironmentVariableW(L"GSTheme", OMDPreferredThemeName(runtimeRoot));
    }

    if (!OMDBuildChildCommandLine(commandBuffer, OMD_MAX_PATH, appPath)) {
        OMDShowError(L"Unable to prepare the application command line.");
        return 1;
    }

    ZeroMemory(&startupInfo, sizeof(startupInfo));
    startupInfo.cb = sizeof(startupInfo);
    ZeroMemory(&processInfo, sizeof(processInfo));

    if (!CreateProcessW(appPath,
                        commandBuffer,
                        NULL,
                        NULL,
                        FALSE,
                        CREATE_UNICODE_ENVIRONMENT,
                        NULL,
                        rootDir,
                        &startupInfo,
                        &processInfo)) {
        swprintf(errorBuffer,
                 OMD_MAX_PATH,
                 L"Failed to launch MarkdownViewer.\n\nWindows error code: %lu",
                 GetLastError());
        OMDShowError(errorBuffer);
        return 1;
    }

    CloseHandle(processInfo.hThread);
    CloseHandle(processInfo.hProcess);
    return 0;
}
