// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDWindowsMenuBar.h"
#import "OMDViewerDiagnostics.h"

#if defined(_WIN32)
#include <windows.h>
#include <stdio.h>

typedef struct {
    NSString *title;
    NSMenuItem *item;
    BOOL topLevel;
    BOOL separator;
    BOOL checked;
    BOOL enabled;
} OMDWindowsMenuItemData;

static WNDPROC OMDOriginalWindowsMenuWndProc = NULL;
static NSMutableArray *OMDWindowsMenuItemDataStorage = nil;
static NSMutableDictionary *OMDWindowsMenuItemsByCommandID = nil;

static const int OMDWinUIMenuTopHeight = 32;
static const int OMDWinUIMenuItemHeight = 32;
static const int OMDWinUIMenuSeparatorHeight = 8;
static const int OMDWinUIMenuCheckColumnWidth = 28;
static const int OMDWinUIMenuLeftTextPadding = 12;
static const int OMDWinUIMenuRightPadding = 20;
static const int OMDWinUIMenuSubmenuPadding = 32;
static const int OMDWinUIMenuHoverInsetX = 4;
static const int OMDWinUIMenuHoverInsetY = 2;
static const int OMDWinUIMenuHoverRadius = 8;
static const int OMDWinUIMenuTopTextYOffset = 3;
static const int OMDWinUIMenuTopHoverInsetTop = 2;
static const int OMDWinUIMenuTopHoverOutsetBottom = 4;
static const int OMDWinUIMenuPopupYOffset = 6;
static const UINT_PTR OMDWinUIMenuPopupAdjustTimer = 0x4F4D4455;
static const int OMDWinUIMenuSubmenuChevronOffset = 14;
static const UINT_PTR OMDWinUIMenuPopupChevronTimer = 0x4F4D4457;

#define OMDWinUIMenuBarBackground RGB(243, 243, 243)
#define OMDWinUIMenuFlyoutBackground RGB(255, 255, 255)
#define OMDWinUIMenuTopHover RGB(229, 229, 229)
#define OMDWinUIMenuItemHover RGB(243, 243, 243)
#define OMDWinUIMenuSeparator RGB(224, 224, 224)
#define OMDWinUIMenuText RGB(32, 32, 32)
#define OMDWinUIMenuDisabledText RGB(150, 150, 150)

static HFONT OMDWindowsMenuFont(void)
{
    static HFONT menuFont = NULL;
    if (menuFont == NULL) {
        menuFont = CreateFontW(-14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    }
    return menuFont;
}

static OMDWindowsMenuItemData *OMDCreateWindowsMenuItemData(NSMenuItem *item, BOOL topLevel, BOOL separator)
{
    OMDWindowsMenuItemData *data = (OMDWindowsMenuItemData *)calloc(1, sizeof(OMDWindowsMenuItemData));
    if (data == NULL) {
        return NULL;
    }
    data->title = separator ? [@"" copy] : [[item title] copy];
    data->item = separator ? nil : [item retain];
    data->topLevel = topLevel;
    data->separator = separator;
    data->checked = (separator || item == nil) ? NO : ([item state] == NSOnState);
    data->enabled = separator ? NO : [item isEnabled];
    if (OMDWindowsMenuItemDataStorage == nil) {
        OMDWindowsMenuItemDataStorage = [[NSMutableArray alloc] init];
    }
    [OMDWindowsMenuItemDataStorage addObject:[NSValue valueWithPointer:data]];
    return data;
}

static void OMDDrawWindowsMenuText(HDC hdc, NSString *title, RECT rect, COLORREF color, UINT format)
{
    NSUInteger length = [title length];
    unichar *characters = NULL;

    if (length == 0) {
        return;
    }

    characters = (unichar *)calloc(length + 1, sizeof(unichar));
    if (characters == NULL) {
        return;
    }

    [title getCharacters:characters range:NSMakeRange(0, length)];
    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, color);
    DrawTextW(hdc, (LPCWSTR)characters, (int)length, &rect, format);
    free(characters);
}

static void OMDDrawWindowsMenuTextCentered(HDC hdc, NSString *title, RECT rect, COLORREF color, UINT format, int yOffset)
{
    NSUInteger length = [title length];
    unichar *characters = NULL;
    SIZE textSize;
    RECT textRect = rect;

    if (length == 0) {
        return;
    }

    characters = (unichar *)calloc(length + 1, sizeof(unichar));
    if (characters == NULL) {
        return;
    }

    memset(&textSize, 0, sizeof(textSize));
    [title getCharacters:characters range:NSMakeRange(0, length)];
    GetTextExtentPoint32W(hdc, (LPCWSTR)characters, (int)length, &textSize);
    textRect.top = rect.top + (((rect.bottom - rect.top) - textSize.cy) / 2) + yOffset;
    textRect.bottom = textRect.top + textSize.cy + 2;
    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, color);
    DrawTextW(hdc, (LPCWSTR)characters, (int)length, &textRect,
              (format & ~DT_VCENTER) | DT_TOP);
    free(characters);
}

static void OMDDrawWindowsMenuCheckmark(HDC hdc, RECT rect, COLORREF color)
{
    HPEN pen = CreatePen(PS_SOLID, 2, color);
    HPEN oldPen = NULL;
    int left = rect.left + 11;
    int centerY = rect.top + ((rect.bottom - rect.top) / 2);

    if (pen == NULL) {
        return;
    }

    oldPen = (HPEN)SelectObject(hdc, pen);
    MoveToEx(hdc, left, centerY, NULL);
    LineTo(hdc, left + 4, centerY + 4);
    LineTo(hdc, left + 12, centerY - 5);
    if (oldPen != NULL) {
        SelectObject(hdc, oldPen);
    }
    DeleteObject(pen);
}

static void OMDDrawWindowsMenuSubmenuChevronAt(HDC hdc, int centerX, int centerY, COLORREF color)
{
    HPEN pen = CreatePen(PS_SOLID, 1, color);
    HPEN oldPen = NULL;

    if (pen == NULL) {
        return;
    }

    oldPen = (HPEN)SelectObject(hdc, pen);
    MoveToEx(hdc, centerX - 2, centerY - 4, NULL);
    LineTo(hdc, centerX + 2, centerY);
    LineTo(hdc, centerX - 2, centerY + 4);
    if (oldPen != NULL) {
        SelectObject(hdc, oldPen);
    }
    DeleteObject(pen);
}

static void OMDRepaintWindowsMenuPopupChevronRow(HWND popupHwnd)
{
    HDC hdc = NULL;
    RECT rect;
    int width = 0;
    int height = 0;
    int centerY = 0;
    int centerX = 0;
    RECT coverRect;
    COLORREF fillColor = OMDWinUIMenuFlyoutBackground;
    HBRUSH coverBrush = NULL;

    if (popupHwnd == NULL || GetWindowRect(popupHwnd, &rect) == 0) {
        return;
    }

    width = rect.right - rect.left;
    height = rect.bottom - rect.top;
    if (width < 180 || height < 120) {
        return;
    }

    hdc = GetWindowDC(popupHwnd);
    if (hdc == NULL) {
        return;
    }

    centerY = 1 + (OMDWinUIMenuItemHeight * 2) + (OMDWinUIMenuItemHeight / 2);
    centerX = width - OMDWinUIMenuSubmenuChevronOffset;
    fillColor = GetPixel(hdc, MAX(0, width - 42), centerY);
    if (fillColor == CLR_INVALID) {
        fillColor = OMDWinUIMenuFlyoutBackground;
    }

    coverRect.left = MAX(0, width - 36);
    coverRect.right = width - 4;
    coverRect.top = MAX(0, centerY - 13);
    coverRect.bottom = MIN(height, centerY + 14);
    coverBrush = CreateSolidBrush(fillColor);
    if (coverBrush != NULL) {
        FillRect(hdc, &coverRect, coverBrush);
        DeleteObject(coverBrush);
    }
    OMDDrawWindowsMenuSubmenuChevronAt(hdc, centerX, centerY, OMDWinUIMenuText);

    ReleaseDC(popupHwnd, hdc);
}

static LRESULT CALLBACK OMDWindowsMenuPopupWindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    WNDPROC originalProc = (WNDPROC)GetPropW(hwnd, L"OMDWinUIMenuPopupOriginalProc");
    LRESULT result = 0;

    if (originalProc != NULL) {
        result = CallWindowProcW(originalProc, hwnd, message, wParam, lParam);
    } else {
        result = DefWindowProcW(hwnd, message, wParam, lParam);
    }

    if (message == WM_PAINT || message == WM_NCPAINT || message == WM_MOUSEMOVE) {
        OMDRepaintWindowsMenuPopupChevronRow(hwnd);
        SetTimer(hwnd, OMDWinUIMenuPopupChevronTimer, 20, NULL);
    } else if (message == WM_TIMER && (UINT_PTR)wParam == OMDWinUIMenuPopupChevronTimer) {
        OMDRepaintWindowsMenuPopupChevronRow(hwnd);
        return 0;
    } else if (message == WM_NCDESTROY) {
        KillTimer(hwnd, OMDWinUIMenuPopupChevronTimer);
        RemovePropW(hwnd, L"OMDWinUIMenuPopupOriginalProc");
    }

    return result;
}

static void OMDDrawWindowsMenuItem(const DRAWITEMSTRUCT *drawItem)
{
    OMDWindowsMenuItemData *data = (OMDWindowsMenuItemData *)drawItem->itemData;
    HDC hdc = drawItem->hDC;
    RECT rect = drawItem->rcItem;
    BOOL selected = ((drawItem->itemState & ODS_SELECTED) != 0);
    BOOL disabled = ((drawItem->itemState & ODS_DISABLED) != 0) || !data->enabled;
    BOOL active = selected && !disabled;
    COLORREF background = data->topLevel ? OMDWinUIMenuBarBackground : OMDWinUIMenuFlyoutBackground;
    COLORREF selection = data->topLevel ? OMDWinUIMenuTopHover : OMDWinUIMenuItemHover;
    COLORREF text = disabled ? OMDWinUIMenuDisabledText : OMDWinUIMenuText;
    HBRUSH brush = CreateSolidBrush(background);
    HFONT oldFont = NULL;

    FillRect(hdc, &rect, brush);
    DeleteObject(brush);

    if (data->separator) {
        RECT separatorRect = rect;
        HBRUSH separatorBrush = CreateSolidBrush(OMDWinUIMenuSeparator);
        separatorRect.left += OMDWinUIMenuCheckColumnWidth + OMDWinUIMenuLeftTextPadding;
        separatorRect.right -= 12;
        separatorRect.top = rect.top + ((rect.bottom - rect.top) / 2);
        separatorRect.bottom = separatorRect.top + 1;
        FillRect(hdc, &separatorRect, separatorBrush);
        DeleteObject(separatorBrush);
        return;
    }

    oldFont = (HFONT)SelectObject(hdc, OMDWindowsMenuFont());

    if (data->topLevel) {
        RECT pillRect = rect;
        RECT textRect = rect;
        pillRect.left += OMDWinUIMenuHoverInsetX;
        pillRect.right -= OMDWinUIMenuHoverInsetX;
        pillRect.top += OMDWinUIMenuTopHoverInsetTop;
        pillRect.bottom += OMDWinUIMenuTopHoverOutsetBottom;
        if (active) {
            HBRUSH selectionBrush = CreateSolidBrush(selection);
            HPEN selectionPen = CreatePen(PS_SOLID, 1, selection);
            HBRUSH oldBrush = (HBRUSH)SelectObject(hdc, selectionBrush);
            HPEN oldPen = (HPEN)SelectObject(hdc, selectionPen);
            RoundRect(hdc, pillRect.left, pillRect.top, pillRect.right, pillRect.bottom,
                      OMDWinUIMenuHoverRadius, OMDWinUIMenuHoverRadius);
            SelectObject(hdc, oldPen);
            SelectObject(hdc, oldBrush);
            DeleteObject(selectionPen);
            DeleteObject(selectionBrush);
        }
        textRect.left += 12;
        textRect.right -= 12;
        OMDDrawWindowsMenuTextCentered(hdc, data->title, textRect, text,
                                       DT_SINGLELINE | DT_CENTER | DT_VCENTER | DT_NOPREFIX,
                                       OMDWinUIMenuTopTextYOffset);
    } else {
        RECT textRect = rect;
        BOOL hasSubmenu = ([data->item submenu] != nil);
        if (active) {
            RECT selectionRect = rect;
            HBRUSH selectionBrush = CreateSolidBrush(selection);
            HPEN selectionPen = CreatePen(PS_SOLID, 1, selection);
            HBRUSH oldBrush = (HBRUSH)SelectObject(hdc, selectionBrush);
            HPEN oldPen = (HPEN)SelectObject(hdc, selectionPen);
            selectionRect.left += OMDWinUIMenuHoverInsetX;
            selectionRect.right -= OMDWinUIMenuHoverInsetX;
            selectionRect.top += OMDWinUIMenuHoverInsetY;
            selectionRect.bottom -= OMDWinUIMenuHoverInsetY;
            RoundRect(hdc, selectionRect.left, selectionRect.top, selectionRect.right, selectionRect.bottom,
                      OMDWinUIMenuHoverRadius, OMDWinUIMenuHoverRadius);
            SelectObject(hdc, oldPen);
            SelectObject(hdc, oldBrush);
            DeleteObject(selectionPen);
            DeleteObject(selectionBrush);
        }
        if (data->checked) {
            OMDDrawWindowsMenuCheckmark(hdc, rect, text);
        }
        if (hasSubmenu) {
            RECT nativeArrowCoverRect = rect;
            HBRUSH coverBrush = CreateSolidBrush(active ? selection : background);
            nativeArrowCoverRect.left = MAX(rect.left, rect.right - 36);
            FillRect(hdc, &nativeArrowCoverRect, coverBrush);
            DeleteObject(coverBrush);
        }
        textRect.left += OMDWinUIMenuCheckColumnWidth + OMDWinUIMenuLeftTextPadding;
        textRect.right -= (hasSubmenu ? OMDWinUIMenuSubmenuPadding : OMDWinUIMenuRightPadding);
        OMDDrawWindowsMenuText(hdc, data->title, textRect, text,
                               DT_SINGLELINE | DT_LEFT | DT_VCENTER | DT_NOPREFIX);
        if (hasSubmenu) {
            OMDDrawWindowsMenuSubmenuChevronAt(hdc,
                                               rect.right - OMDWinUIMenuSubmenuChevronOffset,
                                               rect.top + ((rect.bottom - rect.top) / 2),
                                               OMDWinUIMenuText);
        }
    }

    if (oldFont != NULL) {
        SelectObject(hdc, oldFont);
    }
}

static WINBOOL CALLBACK OMDAdjustWindowsMenuPopupWindow(HWND popupHwnd, LPARAM ownerParam)
{
    HWND ownerHwnd = (HWND)ownerParam;
    DWORD popupProcessID = 0;
    DWORD ownerProcessID = 0;
    WCHAR className[64];
    RECT popupRect;
    RECT ownerRect;

    if (popupHwnd == NULL || ownerHwnd == NULL || !IsWindowVisible(popupHwnd)) {
        return TRUE;
    }

    GetWindowThreadProcessId(popupHwnd, &popupProcessID);
    GetWindowThreadProcessId(ownerHwnd, &ownerProcessID);
    if (popupProcessID != ownerProcessID) {
        return TRUE;
    }

    memset(className, 0, sizeof(className));
    GetClassNameW(popupHwnd, className, (int)(sizeof(className) / sizeof(className[0])));
    if (wcscmp(className, L"#32768") != 0) {
        return TRUE;
    }

    if (GetWindowRect(popupHwnd, &popupRect) == 0 || GetWindowRect(ownerHwnd, &ownerRect) == 0) {
        return TRUE;
    }

    if (GetPropW(popupHwnd, L"OMDWinUIMenuPopupAdjusted") != NULL) {
        return TRUE;
    }

    if (popupRect.left >= ownerRect.left - 4
        && popupRect.left <= ownerRect.right
        && popupRect.top >= ownerRect.top + 35
        && popupRect.top <= ownerRect.top + 75) {
        SetWindowPos(popupHwnd,
                     NULL,
                     popupRect.left,
                     popupRect.top + OMDWinUIMenuPopupYOffset,
                     0,
                     0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        SetPropW(popupHwnd, L"OMDWinUIMenuPopupAdjusted", (HANDLE)1);
    }

    if (GetPropW(popupHwnd, L"OMDWinUIMenuPopupOriginalProc") == NULL) {
        WNDPROC originalProc = (WNDPROC)GetWindowLongPtrW(popupHwnd, GWLP_WNDPROC);
        if (originalProc != NULL && originalProc != OMDWindowsMenuPopupWindowProc) {
            SetPropW(popupHwnd, L"OMDWinUIMenuPopupOriginalProc", (HANDLE)originalProc);
            SetWindowLongPtrW(popupHwnd, GWLP_WNDPROC, (LONG_PTR)OMDWindowsMenuPopupWindowProc);
            SetTimer(popupHwnd, OMDWinUIMenuPopupChevronTimer, 20, NULL);
        }
    }
    OMDRepaintWindowsMenuPopupChevronRow(popupHwnd);

    return TRUE;
}

static void OMDAdjustWindowsMenuPopupWindows(HWND ownerHwnd)
{
    EnumWindows(OMDAdjustWindowsMenuPopupWindow, (LPARAM)ownerHwnd);
}

static LRESULT CALLBACK OMDWindowsMenuWindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    if (message == WM_MEASUREITEM) {
        MEASUREITEMSTRUCT *measure = (MEASUREITEMSTRUCT *)lParam;
        OMDWindowsMenuItemData *data = (OMDWindowsMenuItemData *)measure->itemData;
        if (measure != NULL && measure->CtlType == ODT_MENU && data != NULL) {
            HDC hdc = GetDC(hwnd);
            HFONT oldFont = NULL;
            SIZE textSize;
            NSUInteger length = [data->title length];
            unichar *characters = (unichar *)calloc(length + 1, sizeof(unichar));
            memset(&textSize, 0, sizeof(textSize));
            if (hdc != NULL) {
                oldFont = (HFONT)SelectObject(hdc, OMDWindowsMenuFont());
            }
            if (characters != NULL) {
                [data->title getCharacters:characters range:NSMakeRange(0, length)];
                GetTextExtentPoint32W(hdc, (LPCWSTR)characters, (int)length, &textSize);
                free(characters);
            }
            if (oldFont != NULL) {
                SelectObject(hdc, oldFont);
            }
            ReleaseDC(hwnd, hdc);
            measure->itemWidth = (UINT)(data->separator
                                        ? 240
                                        : textSize.cx + (data->topLevel
                                                         ? 32
                                                         : OMDWinUIMenuCheckColumnWidth + OMDWinUIMenuLeftTextPadding + OMDWinUIMenuSubmenuPadding));
            measure->itemHeight = (UINT)(data->separator
                                         ? OMDWinUIMenuSeparatorHeight
                                         : (data->topLevel ? OMDWinUIMenuTopHeight : OMDWinUIMenuItemHeight));
            return TRUE;
        }
    } else if (message == WM_DRAWITEM) {
        DRAWITEMSTRUCT *drawItem = (DRAWITEMSTRUCT *)lParam;
        if (drawItem != NULL && drawItem->CtlType == ODT_MENU && drawItem->itemData != 0) {
            OMDDrawWindowsMenuItem(drawItem);
            return TRUE;
        }
    } else if (message == WM_INITMENUPOPUP) {
        SetTimer(hwnd, OMDWinUIMenuPopupAdjustTimer, 1, NULL);
    } else if (message == WM_TIMER) {
        if ((UINT_PTR)wParam == OMDWinUIMenuPopupAdjustTimer) {
            KillTimer(hwnd, OMDWinUIMenuPopupAdjustTimer);
            OMDAdjustWindowsMenuPopupWindows(hwnd);
            return 0;
        }
    } else if (message == WM_COMMAND) {
        UINT commandID = LOWORD(wParam);
        NSValue *itemValue = [OMDWindowsMenuItemsByCommandID objectForKey:[NSNumber numberWithUnsignedInt:commandID]];
        NSMenuItem *item = [itemValue pointerValue];
        if (item != nil && [item action] != NULL) {
            [NSApp sendAction:[item action] to:[item target] from:item];
            return 0;
        }
    }

    if (OMDOriginalWindowsMenuWndProc != NULL) {
        return CallWindowProcW(OMDOriginalWindowsMenuWndProc, hwnd, message, wParam, lParam);
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

static void OMDEnsureWindowsMenuSubclass(HWND hwnd)
{
    LONG_PTR currentProc = GetWindowLongPtrW(hwnd, GWLP_WNDPROC);
    if ((WNDPROC)currentProc == OMDWindowsMenuWindowProc) {
        return;
    }
    OMDOriginalWindowsMenuWndProc = (WNDPROC)currentProc;
    SetWindowLongPtrW(hwnd, GWLP_WNDPROC, (LONG_PTR)OMDWindowsMenuWindowProc);
}

static void OMDAppendNativeWindowsMenuItems(HMENU nativeMenu, NSMenu *menu, UINT *nextCommandID, BOOL topLevel)
{
    NSUInteger count = [menu numberOfItems];
    NSUInteger index = 0;

    for (index = 0; index < count; index++) {
        NSMenuItem *item = [menu itemAtIndex:index];
        OMDWindowsMenuItemData *data = NULL;
        UINT flags = MF_OWNERDRAW;

        if (item == nil) {
            continue;
        }
        if ([item respondsToSelector:@selector(isHidden)]) {
            BOOL (*isHiddenImp)(id, SEL) = (BOOL (*)(id, SEL))[item methodForSelector:@selector(isHidden)];
            if (isHiddenImp != NULL && isHiddenImp(item, @selector(isHidden))) {
                continue;
            }
        }
        if ([item isSeparatorItem]) {
            data = OMDCreateWindowsMenuItemData(item, topLevel, YES);
            if (data != NULL) {
                AppendMenuW(nativeMenu, MF_OWNERDRAW | MF_GRAYED, 0, (LPCWSTR)data);
            }
            continue;
        }
        if (topLevel && index == 0) {
            NSString *title = [item title];
            NSString *processName = [[NSProcessInfo processInfo] processName];
            if ([title isEqualToString:processName] || [title isEqualToString:@"MarkdownViewer"]) {
                continue;
            }
        }

        if ([item target] != nil
            && [[item target] respondsToSelector:@selector(validateMenuItem:)]) {
            BOOL valid = [(id)[item target] validateMenuItem:item];
            if (!valid) {
                [item setEnabled:NO];
            }
        }

        data = OMDCreateWindowsMenuItemData(item, topLevel, NO);
        if (data == NULL) {
            continue;
        }
        if (![item isEnabled]) {
            flags |= MF_GRAYED;
        }

        if ([item submenu] != nil) {
            HMENU nativeSubmenu = CreatePopupMenu();
            OMDAppendNativeWindowsMenuItems(nativeSubmenu, [item submenu], nextCommandID, NO);
            AppendMenuW(nativeMenu, flags | MF_POPUP, (UINT_PTR)nativeSubmenu, (LPCWSTR)data);
        } else {
            UINT commandID = (*nextCommandID)++;
            if (OMDWindowsMenuItemsByCommandID == nil) {
                OMDWindowsMenuItemsByCommandID = [[NSMutableDictionary alloc] init];
            }
            [OMDWindowsMenuItemsByCommandID setObject:[NSValue valueWithPointer:item]
                                               forKey:[NSNumber numberWithUnsignedInt:commandID]];
            AppendMenuW(nativeMenu, flags, commandID, (LPCWSTR)data);
        }
    }
}

void OMDInstallWinUIStyleWindowsMenuBar(NSWindow *window, NSMenu *menu)
{
    HWND hwnd = NULL;
    HMENU nativeMenu = NULL;
    MENUINFO menuInfo;
    static HBRUSH menuBackgroundBrush = NULL;
    UINT nextCommandID = 1000;

    if (window == nil || menu == nil || ![window respondsToSelector:@selector(windowHandle)]) {
        return;
    }

    hwnd = (HWND)[window windowHandle];
    if (hwnd == NULL) {
        return;
    }

    if (menuBackgroundBrush == NULL) {
        menuBackgroundBrush = CreateSolidBrush(RGB(243, 243, 243));
    }

    [OMDWindowsMenuItemsByCommandID removeAllObjects];
    nativeMenu = CreateMenu();
    memset(&menuInfo, 0, sizeof(menuInfo));
    menuInfo.cbSize = sizeof(menuInfo);
    menuInfo.fMask = MIM_BACKGROUND;
    menuInfo.hbrBack = menuBackgroundBrush;
    SetMenuInfo(nativeMenu, &menuInfo);

    OMDAppendNativeWindowsMenuItems(nativeMenu, menu, &nextCommandID, YES);
    OMDEnsureWindowsMenuSubclass(hwnd);
    if (SetMenu(hwnd, nativeMenu)) {
        DrawMenuBar(hwnd);
        OMDStartupTrace(@"WinUI-style Windows menu bar installed");
    }
}
#endif
