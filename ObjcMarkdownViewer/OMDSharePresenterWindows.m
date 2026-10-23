// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSharePresenter.h"
#import "OMDWindowsClipboard.h"

#if defined(GNUSTEP) && defined(_WIN32)
// Windows: the Windows share sheet (DataTransferManager through
// IDataTransferManagerInterop), Simple MAPI for email, and Explorer for
// Show in Folder (#178). Where the share sheet isn't there (Windows
// Server, older builds) or doesn't open, the basic presenter's notice
// takes over; where MAPI can't send (no client, the new Outlook, webmail),
// the mailto: draft does.
@interface OMDSharePresenterWindows : OMDShareBasicPresenter
{
    void *_requestHandler;
    void *_transferManager;
    long long _requestToken;
    OMDShareItem *_pendingItem;
    NSView *_pendingView;
}
@end

#include <windows.h>
// GNUstep's headers include windows.h and then undefine its "interface"
// (it would turn @interface into @struct); the COM headers below need it.
#define interface struct
#include <roapi.h>
#include <winstring.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <windows.applicationmodel.datatransfer.h>
#include <windows.storage.h>
#undef interface

// The C names of the WinRT interfaces used here.
typedef __x_ABI_CWindows_CApplicationModel_CDataTransfer_CIDataTransferManager OMDDataTransferManager;
typedef __x_ABI_CWindows_CApplicationModel_CDataTransfer_CIDataTransferManagerStatics2 OMDDataTransferManagerStatics2;
typedef __x_ABI_CWindows_CApplicationModel_CDataTransfer_CIDataRequestedEventArgs OMDDataRequestedEventArgs;
typedef __x_ABI_CWindows_CApplicationModel_CDataTransfer_CIDataRequest OMDDataRequest;
typedef __x_ABI_CWindows_CApplicationModel_CDataTransfer_CIDataPackage OMDDataPackage;
typedef __x_ABI_CWindows_CApplicationModel_CDataTransfer_CIDataPackagePropertySet OMDDataPackagePropertySet;
typedef __FITypedEventHandler_2_Windows__CApplicationModel__CDataTransfer__CDataTransferManager_Windows__CApplicationModel__CDataTransfer__CDataRequestedEventArgs OMDRequestedHandler;
typedef __FITypedEventHandler_2_Windows__CApplicationModel__CDataTransfer__CDataTransferManager_Windows__CApplicationModel__CDataTransfer__CDataRequestedEventArgsVtbl OMDRequestedHandlerVtbl;
typedef __FIIterable_1_Windows__CStorage__CIStorageItem OMDStorageItemIterable;
typedef __FIIterable_1_Windows__CStorage__CIStorageItemVtbl OMDStorageItemIterableVtbl;
typedef __FIIterator_1_Windows__CStorage__CIStorageItem OMDStorageItemIterator;
typedef __FIIterator_1_Windows__CStorage__CIStorageItemVtbl OMDStorageItemIteratorVtbl;
typedef __FIAsyncOperation_1_Windows__CStorage__CStorageFile OMDStorageFileOperation;
typedef __x_ABI_CWindows_CStorage_CIStorageFile OMDStorageFile;
typedef __x_ABI_CWindows_CStorage_CIStorageItem OMDStorageItem;

// MinGW-w64 declares these IIDs without defining them (and has no
// IID_IDataTransferManagerInterop), so they are spelled out here.
static const IID OMDIID_DataTransferManagerInterop = {0x3a3dcd6c, 0x3eab, 0x43dc, {0xbc, 0xde, 0x45, 0x67, 0x1c, 0xe8, 0x00, 0xc8}};
static const IID OMDIID_DataTransferManager = {0xa5caee9b, 0x8708, 0x49d1, {0x8d, 0x36, 0x67, 0xd2, 0x5a, 0x8d, 0xa0, 0x0c}};
static const IID OMDIID_DataTransferManagerStatics2 = {0xc54ec2ec, 0x9f97, 0x4d63, {0x98, 0x68, 0x39, 0x5e, 0x27, 0x1a, 0xd8, 0xf5}};
static const IID OMDIID_RequestedHandler = {0xec6f9cc8, 0x46d0, 0x5e0e, {0xb4, 0xd2, 0x7d, 0x77, 0x73, 0xae, 0x37, 0xa0}};
static const IID OMDIID_StorageItemIterable = {0xbb8b8418, 0x65d1, 0x544b, {0xb0, 0x83, 0x6d, 0x17, 0x2f, 0x56, 0x8c, 0x73}};
static const IID OMDIID_StorageItemIterator = {0x05b487c2, 0x3830, 0x5d3c, {0x98, 0xda, 0x25, 0xfa, 0x11, 0x54, 0x2d, 0xbd}};
static const IID OMDIID_StorageItem = {0x4207a996, 0xca2f, 0x42f7, {0xbd, 0xe8, 0x8b, 0x10, 0x45, 0x7a, 0x7f, 0x30}};
static const IID OMDIID_StorageFileStatics = {0x5984c710, 0xdaf2, 0x43c8, {0x8b, 0xb4, 0xa4, 0xd3, 0xea, 0xcf, 0xd0, 0x3f}};
static const IID OMDIID_AsyncInfo = {0x00000036, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const IID OMDIID_Unknown = {0x00000000, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const IID OMDIID_Inspectable = {0xaf86e2e0, 0xb12d, 0x4c6a, {0x9c, 0x5a, 0xd7, 0xaa, 0x65, 0x10, 0x1e, 0x90}};
static const IID OMDIID_AgileObject = {0x94ea2b94, 0xe9cc, 0x49e0, {0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90}};

// Windows.Storage.StorageFile's statics, which MinGW-w64 only
// forward-declares; the layout is the Windows SDK's (windows.storage.idl),
// and only the first method is called.
typedef struct OMDStorageFileStatics OMDStorageFileStatics;
typedef struct OMDStorageFileStaticsVtbl {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(OMDStorageFileStatics *This, REFIID riid, void **object);
    ULONG (STDMETHODCALLTYPE *AddRef)(OMDStorageFileStatics *This);
    ULONG (STDMETHODCALLTYPE *Release)(OMDStorageFileStatics *This);
    HRESULT (STDMETHODCALLTYPE *GetIids)(OMDStorageFileStatics *This, ULONG *count, IID **iids);
    HRESULT (STDMETHODCALLTYPE *GetRuntimeClassName)(OMDStorageFileStatics *This, HSTRING *name);
    HRESULT (STDMETHODCALLTYPE *GetTrustLevel)(OMDStorageFileStatics *This, TrustLevel *level);
    HRESULT (STDMETHODCALLTYPE *GetFileFromPathAsync)(OMDStorageFileStatics *This, HSTRING path, OMDStorageFileOperation **operation);
} OMDStorageFileStaticsVtbl;
struct OMDStorageFileStatics {
    const OMDStorageFileStaticsVtbl *lpVtbl;
};

// A NUL-terminated UTF-16 copy of a string, valid until the autorelease
// pool drains.
static const wchar_t *OMDWideString(NSString *string)
{
    NSMutableData *data = [NSMutableData dataWithData:[(string != nil ? string : @"") dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
    unichar terminator = 0;
    [data appendBytes:&terminator length:sizeof(terminator)];
    return (const wchar_t *)[data bytes];
}

static NSString *OMDWindowsPath(NSURL *url)
{
    return [[url path] stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
}

static HSTRING OMDCreateHString(const wchar_t *text)
{
    HSTRING string = NULL;
    if (FAILED(WindowsCreateString(text, (UINT32)wcslen(text), &string))) {
        return NULL;
    }
    return string;
}

static HRESULT OMDGetActivationFactory(const wchar_t *className, REFIID iid, void **factory)
{
    HSTRING name = OMDCreateHString(className);
    if (name == NULL) {
        return E_OUTOFMEMORY;
    }
    HRESULT result = RoGetActivationFactory(name, iid, factory);
    WindowsDeleteString(name);
    return result;
}

// WinRT is used from the GNUstep main thread, which is an STA (or already
// initialized as one by OLE); either way the calls below work.
static void OMDEnsureWindowsRuntime(void)
{
    static BOOL initialized = NO;
    if (!initialized) {
        RoInitialize(RO_INIT_SINGLETHREADED);
        initialized = YES;
    }
}

static BOOL OMDShareSheetIsSupported(void)
{
    OMDEnsureWindowsRuntime();
    OMDDataTransferManagerStatics2 *statics = NULL;
    if (FAILED(OMDGetActivationFactory(L"Windows.ApplicationModel.DataTransfer.DataTransferManager",
                                       &OMDIID_DataTransferManagerStatics2, (void **)&statics))) {
        return NO;
    }
    boolean supported = 0;
    HRESULT result = statics->lpVtbl->IsSupported(statics, &supported);
    statics->lpVtbl->Release(statics);
    return SUCCEEDED(result) && supported;
}

// The file as a Windows.Storage.StorageFile, +1 retained, or NULL. The
// lookup is asynchronous; it is quick for a local file, so it is waited
// for here (at most two seconds), before the share sheet opens.
// path is a Windows path.
static OMDStorageItem *OMDCreateStorageItemForPath(NSString *path)
{
    OMDEnsureWindowsRuntime();
    OMDStorageFileStatics *files = NULL;
    if (FAILED(OMDGetActivationFactory(L"Windows.Storage.StorageFile", &OMDIID_StorageFileStatics, (void **)&files))) {
        return NULL;
    }
    HSTRING pathString = OMDCreateHString(OMDWideString(path));
    OMDStorageFileOperation *operation = NULL;
    HRESULT result = pathString != NULL ? files->lpVtbl->GetFileFromPathAsync(files, pathString, &operation) : E_OUTOFMEMORY;
    if (pathString != NULL) {
        WindowsDeleteString(pathString);
    }
    files->lpVtbl->Release(files);
    if (FAILED(result) || operation == NULL) {
        return NULL;
    }

    IAsyncInfo *info = NULL;
    AsyncStatus status = Started;
    if (SUCCEEDED(operation->lpVtbl->QueryInterface(operation, &OMDIID_AsyncInfo, (void **)&info))) {
        for (int waited = 0; waited < 200; waited++) {
            if (FAILED(info->lpVtbl->get_Status(info, &status)) || status != Started) {
                break;
            }
            Sleep(10);
        }
        info->lpVtbl->Release(info);
    }

    OMDStorageFile *file = NULL;
    OMDStorageItem *item = NULL;
    if (status == Completed && SUCCEEDED(operation->lpVtbl->GetResults(operation, &file)) && file != NULL) {
        file->lpVtbl->QueryInterface(file, &OMDIID_StorageItem, (void **)&item);
        file->lpVtbl->Release(file);
    }
    operation->lpVtbl->Release(operation);
    return item;
}

// A one-item IIterable<IStorageItem*>, what IDataPackage takes as files.
typedef struct OMDOneItemIterator {
    const OMDStorageItemIteratorVtbl *lpVtbl;
    LONG references;
    OMDStorageItem *item;
    BOOL done;
} OMDOneItemIterator;

typedef struct OMDOneItemIterable {
    const OMDStorageItemIterableVtbl *lpVtbl;
    LONG references;
    OMDStorageItem *item;
} OMDOneItemIterable;

static HRESULT STDMETHODCALLTYPE OMDIteratorQueryInterface(OMDStorageItemIterator *This, REFIID riid, void **object)
{
    if (IsEqualIID(riid, &OMDIID_StorageItemIterator) || IsEqualIID(riid, &OMDIID_Unknown) || IsEqualIID(riid, &OMDIID_Inspectable)) {
        *object = This;
        This->lpVtbl->AddRef(This);
        return S_OK;
    }
    *object = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE OMDIteratorAddRef(OMDStorageItemIterator *This)
{
    return (ULONG)InterlockedIncrement(&((OMDOneItemIterator *)This)->references);
}

static ULONG STDMETHODCALLTYPE OMDIteratorRelease(OMDStorageItemIterator *This)
{
    OMDOneItemIterator *iterator = (OMDOneItemIterator *)This;
    LONG references = InterlockedDecrement(&iterator->references);
    if (references == 0) {
        iterator->item->lpVtbl->Release(iterator->item);
        free(iterator);
    }
    return (ULONG)references;
}

static HRESULT STDMETHODCALLTYPE OMDIteratorGetIids(OMDStorageItemIterator *This, ULONG *count, IID **iids)
{
    (void)This;
    *count = 0;
    *iids = NULL;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE OMDIteratorGetRuntimeClassName(OMDStorageItemIterator *This, HSTRING *name)
{
    (void)This;
    *name = NULL;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE OMDIteratorGetTrustLevel(OMDStorageItemIterator *This, TrustLevel *level)
{
    (void)This;
    *level = BaseTrust;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE OMDIteratorGetCurrent(OMDStorageItemIterator *This, OMDStorageItem **value)
{
    OMDOneItemIterator *iterator = (OMDOneItemIterator *)This;
    if (iterator->done) {
        *value = NULL;
        return E_BOUNDS;
    }
    *value = iterator->item;
    iterator->item->lpVtbl->AddRef(iterator->item);
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE OMDIteratorGetHasCurrent(OMDStorageItemIterator *This, boolean *value)
{
    *value = !((OMDOneItemIterator *)This)->done;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE OMDIteratorMoveNext(OMDStorageItemIterator *This, boolean *value)
{
    ((OMDOneItemIterator *)This)->done = YES;
    *value = 0;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE OMDIteratorGetMany(OMDStorageItemIterator *This, UINT32 capacity, OMDStorageItem **items, UINT32 *count)
{
    OMDOneItemIterator *iterator = (OMDOneItemIterator *)This;
    *count = 0;
    if (!iterator->done && capacity > 0) {
        items[0] = iterator->item;
        iterator->item->lpVtbl->AddRef(iterator->item);
        *count = 1;
        iterator->done = YES;
    }
    return S_OK;
}

static const OMDStorageItemIteratorVtbl OMDOneItemIteratorVtbl = {
    OMDIteratorQueryInterface, OMDIteratorAddRef, OMDIteratorRelease,
    OMDIteratorGetIids, OMDIteratorGetRuntimeClassName, OMDIteratorGetTrustLevel,
    OMDIteratorGetCurrent, OMDIteratorGetHasCurrent, OMDIteratorMoveNext, OMDIteratorGetMany
};

static HRESULT STDMETHODCALLTYPE OMDIterableQueryInterface(OMDStorageItemIterable *This, REFIID riid, void **object)
{
    if (IsEqualIID(riid, &OMDIID_StorageItemIterable) || IsEqualIID(riid, &OMDIID_Unknown) || IsEqualIID(riid, &OMDIID_Inspectable)) {
        *object = This;
        This->lpVtbl->AddRef(This);
        return S_OK;
    }
    *object = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE OMDIterableAddRef(OMDStorageItemIterable *This)
{
    return (ULONG)InterlockedIncrement(&((OMDOneItemIterable *)This)->references);
}

static ULONG STDMETHODCALLTYPE OMDIterableRelease(OMDStorageItemIterable *This)
{
    OMDOneItemIterable *iterable = (OMDOneItemIterable *)This;
    LONG references = InterlockedDecrement(&iterable->references);
    if (references == 0) {
        iterable->item->lpVtbl->Release(iterable->item);
        free(iterable);
    }
    return (ULONG)references;
}

static HRESULT STDMETHODCALLTYPE OMDIterableGetIids(OMDStorageItemIterable *This, ULONG *count, IID **iids)
{
    (void)This;
    *count = 0;
    *iids = NULL;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE OMDIterableGetRuntimeClassName(OMDStorageItemIterable *This, HSTRING *name)
{
    (void)This;
    *name = NULL;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE OMDIterableGetTrustLevel(OMDStorageItemIterable *This, TrustLevel *level)
{
    (void)This;
    *level = BaseTrust;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE OMDIterableFirst(OMDStorageItemIterable *This, OMDStorageItemIterator **value)
{
    OMDOneItemIterator *iterator = calloc(1, sizeof(OMDOneItemIterator));
    if (iterator == NULL) {
        *value = NULL;
        return E_OUTOFMEMORY;
    }
    iterator->lpVtbl = &OMDOneItemIteratorVtbl;
    iterator->references = 1;
    iterator->item = ((OMDOneItemIterable *)This)->item;
    iterator->item->lpVtbl->AddRef(iterator->item);
    *value = (OMDStorageItemIterator *)iterator;
    return S_OK;
}

static const OMDStorageItemIterableVtbl OMDOneItemIterableVtbl = {
    OMDIterableQueryInterface, OMDIterableAddRef, OMDIterableRelease,
    OMDIterableGetIids, OMDIterableGetRuntimeClassName, OMDIterableGetTrustLevel,
    OMDIterableFirst
};

static OMDStorageItemIterable *OMDCreateOneItemIterable(OMDStorageItem *item)
{
    OMDOneItemIterable *iterable = calloc(1, sizeof(OMDOneItemIterable));
    if (iterable == NULL) {
        return NULL;
    }
    iterable->lpVtbl = &OMDOneItemIterableVtbl;
    iterable->references = 1;
    iterable->item = item;
    item->lpVtbl->AddRef(item);
    return (OMDStorageItemIterable *)iterable;
}

// The DataRequested handler: fills the package with the document's title
// and its file when the share sheet asks for them.
typedef struct OMDShareRequestHandler {
    const OMDRequestedHandlerVtbl *lpVtbl;
    LONG references;
    OMDStorageItem *item;
    HSTRING title;
    volatile LONG requested;
} OMDShareRequestHandler;

static HRESULT STDMETHODCALLTYPE OMDHandlerQueryInterface(OMDRequestedHandler *This, REFIID riid, void **object)
{
    if (IsEqualIID(riid, &OMDIID_RequestedHandler) || IsEqualIID(riid, &OMDIID_Unknown) || IsEqualIID(riid, &OMDIID_AgileObject)) {
        *object = This;
        This->lpVtbl->AddRef(This);
        return S_OK;
    }
    *object = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE OMDHandlerAddRef(OMDRequestedHandler *This)
{
    return (ULONG)InterlockedIncrement(&((OMDShareRequestHandler *)This)->references);
}

static ULONG STDMETHODCALLTYPE OMDHandlerRelease(OMDRequestedHandler *This)
{
    OMDShareRequestHandler *handler = (OMDShareRequestHandler *)This;
    LONG references = InterlockedDecrement(&handler->references);
    if (references == 0) {
        handler->item->lpVtbl->Release(handler->item);
        if (handler->title != NULL) {
            WindowsDeleteString(handler->title);
        }
        free(handler);
    }
    return (ULONG)references;
}

static HRESULT STDMETHODCALLTYPE OMDHandlerInvoke(OMDRequestedHandler *This,
                                                  OMDDataTransferManager *sender,
                                                  OMDDataRequestedEventArgs *arguments)
{
    (void)sender;
    OMDShareRequestHandler *handler = (OMDShareRequestHandler *)This;
    InterlockedExchange(&handler->requested, 1);

    OMDDataRequest *request = NULL;
    OMDDataPackage *package = NULL;
    OMDDataPackagePropertySet *properties = NULL;
    if (FAILED(arguments->lpVtbl->get_Request(arguments, &request)) || request == NULL) {
        return S_OK;
    }
    if (SUCCEEDED(request->lpVtbl->get_Data(request, &package)) && package != NULL) {
        // The share sheet shows the title; without one it refuses to share.
        if (SUCCEEDED(package->lpVtbl->get_Properties(package, &properties)) && properties != NULL) {
            properties->lpVtbl->put_Title(properties, handler->title);
            properties->lpVtbl->Release(properties);
        }
        OMDStorageItemIterable *items = OMDCreateOneItemIterable(handler->item);
        if (items != NULL) {
            package->lpVtbl->SetStorageItemsReadOnly(package, items);
            items->lpVtbl->Release(items);
        }
        package->lpVtbl->Release(package);
    }
    request->lpVtbl->Release(request);
    return S_OK;
}

static const OMDRequestedHandlerVtbl OMDShareRequestHandlerVtbl = {
    OMDHandlerQueryInterface, OMDHandlerAddRef, OMDHandlerRelease, OMDHandlerInvoke
};

// Simple MAPI's wide-character API (Windows 8 and later), which MinGW-w64's
// mapi.h doesn't declare; the layouts are the Windows SDK's.
typedef struct OMDMapiRecipDescW {
    ULONG ulReserved;
    ULONG ulRecipClass;
    PWSTR lpszName;
    PWSTR lpszAddress;
    ULONG ulEIDSize;
    PVOID lpEntryID;
} OMDMapiRecipDescW;

typedef struct OMDMapiFileDescW {
    ULONG ulReserved;
    ULONG flFlags;
    ULONG nPosition;
    PWSTR lpszPathName;
    PWSTR lpszFileName;
    PVOID lpFileType;
} OMDMapiFileDescW;

typedef struct OMDMapiMessageW {
    ULONG ulReserved;
    PWSTR lpszSubject;
    PWSTR lpszNoteText;
    PWSTR lpszMessageType;
    PWSTR lpszDateReceived;
    PWSTR lpszConversationID;
    ULONG flFlags;
    OMDMapiRecipDescW *lpOriginator;
    ULONG nRecipCount;
    OMDMapiRecipDescW *lpRecips;
    ULONG nFileCount;
    OMDMapiFileDescW *lpFiles;
} OMDMapiMessageW;

typedef ULONG (WINAPI *OMDMAPISendMailWFunction)(ULONG_PTR session, ULONG_PTR uiParam,
                                                 OMDMapiMessageW *message, ULONG flags, ULONG reserved);

enum {
    OMDMapiLogonUI = 0x00000001,
    OMDMapiDialog = 0x00000008,
    OMDMapiUserAbort = 1,
    OMDMapiSuccess = 0
};

// Whether the default email client takes Simple MAPI: Clients\Mail names
// it (the user's choice first) and its key there names its MAPI DLL. The
// new Outlook, webmail and "none" don't, and mapi32.dll would then show its
// own "no email program" message and report a cancel.
static BOOL OMDDefaultMailClientTakesMapi(void)
{
    static const wchar_t *mailClients = L"Software\\Clients\\Mail";
    wchar_t client[256];
    DWORD size = sizeof(client);
    if (RegGetValueW(HKEY_CURRENT_USER, mailClients, NULL, RRF_RT_REG_SZ, NULL, client, &size) != ERROR_SUCCESS
        || client[0] == 0) {
        size = sizeof(client);
        if (RegGetValueW(HKEY_LOCAL_MACHINE, mailClients, NULL, RRF_RT_REG_SZ, NULL, client, &size) != ERROR_SUCCESS
            || client[0] == 0) {
            return NO;
        }
    }
    wchar_t key[300];
    _snwprintf(key, sizeof(key) / sizeof(key[0]), L"%ls\\%ls", mailClients, client);
    key[sizeof(key) / sizeof(key[0]) - 1] = 0;
    const wchar_t *values[] = { L"DLLPathEx", L"DLLPath" };
    for (unsigned i = 0; i < 2; i++) {
        wchar_t dll[MAX_PATH];
        size = sizeof(dll);
        if (RegGetValueW(HKEY_LOCAL_MACHINE, key, values[i], RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND, NULL, dll, &size) == ERROR_SUCCESS
            && dll[0] != 0) {
            return YES;
        }
    }
    return NO;
}

static HWND OMDWindowHandle(NSWindow *window)
{
    return window != nil ? (HWND)(intptr_t)[window windowNumber] : NULL;
}

@implementation OMDSharePresenterWindows

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self endShareRequest];
    [super dealloc];
}

// Unregisters the last share request's handler.
- (void)endShareRequest
{
    OMDDataTransferManager *manager = (OMDDataTransferManager *)_transferManager;
    OMDRequestedHandler *handler = (OMDRequestedHandler *)_requestHandler;
    if (manager != NULL) {
        EventRegistrationToken token;
        token.value = _requestToken;
        manager->lpVtbl->remove_DataRequested(manager, token);
        manager->lpVtbl->Release(manager);
    }
    if (handler != NULL) {
        handler->lpVtbl->Release(handler);
    }
    _transferManager = NULL;
    _requestHandler = NULL;
    [_pendingItem release];
    _pendingItem = nil;
    [_pendingView release];
    _pendingView = nil;
}

// Where Windows has no share UI (Windows Server), the share controller
// shows the library's sheet instead.
- (BOOL)presentsSystemShareSheet
{
    return OMDShareSheetIsSupported();
}

- (void)presentShareItem:(OMDShareItem *)item fromView:(NSView *)view
{
    HWND window = OMDWindowHandle([view window]);
    if (window == NULL || !OMDShareSheetIsSupported() || ![self showShareSheetForItem:item window:window]) {
        [super presentShareItem:item fromView:view];
        return;
    }
    // ShowShareUIForWindow can succeed without a sheet opening (seen on
    // Windows Server); when the sheet never asks for the data, the notice
    // offers the file instead.
    [_pendingItem release];
    _pendingItem = [item retain];
    [_pendingView release];
    _pendingView = [view retain];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkShareSheetOpened) object:nil];
    [self performSelector:@selector(checkShareSheetOpened) withObject:nil afterDelay:3.0];
}

- (BOOL)showShareSheetForItem:(OMDShareItem *)item window:(HWND)window
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkShareSheetOpened) object:nil];
    [self endShareRequest];

    OMDStorageItem *file = OMDCreateStorageItemForPath(OMDWindowsPath([item fileURL]));
    if (file == NULL) {
        return NO;
    }
    IDataTransferManagerInterop *interop = NULL;
    if (FAILED(OMDGetActivationFactory(L"Windows.ApplicationModel.DataTransfer.DataTransferManager",
                                       &OMDIID_DataTransferManagerInterop, (void **)&interop))) {
        file->lpVtbl->Release(file);
        return NO;
    }
    OMDDataTransferManager *manager = NULL;
    HRESULT result = interop->lpVtbl->GetForWindow(interop, window, &OMDIID_DataTransferManager, (void **)&manager);
    if (FAILED(result) || manager == NULL) {
        interop->lpVtbl->Release(interop);
        file->lpVtbl->Release(file);
        return NO;
    }

    OMDShareRequestHandler *handler = calloc(1, sizeof(OMDShareRequestHandler));
    if (handler == NULL) {
        manager->lpVtbl->Release(manager);
        interop->lpVtbl->Release(interop);
        file->lpVtbl->Release(file);
        return NO;
    }
    handler->lpVtbl = &OMDShareRequestHandlerVtbl;
    handler->references = 1;
    handler->item = file;
    NSString *title = [item title];
    handler->title = OMDCreateHString(OMDWideString([title length] > 0 ? title : [item fileName]));

    EventRegistrationToken token = {0};
    result = manager->lpVtbl->add_DataRequested(manager, (OMDRequestedHandler *)handler, &token);
    if (SUCCEEDED(result)) {
        _transferManager = manager;
        _requestHandler = handler;
        _requestToken = token.value;
        result = interop->lpVtbl->ShowShareUIForWindow(interop, window);
    } else {
        manager->lpVtbl->Release(manager);
        handler->lpVtbl->Release((OMDRequestedHandler *)handler);
    }
    interop->lpVtbl->Release(interop);
    if (FAILED(result)) {
        [self endShareRequest];
        return NO;
    }
    return YES;
}

- (void)checkShareSheetOpened
{
    OMDShareRequestHandler *handler = (OMDShareRequestHandler *)_requestHandler;
    if (handler == NULL || handler->requested) {
        return;
    }
    OMDShareItem *item = [[_pendingItem retain] autorelease];
    NSView *view = [[_pendingView retain] autorelease];
    [self endShareRequest];
    if (item != nil) {
        [super presentShareItem:item fromView:view];
    }
}

- (void)emailShareItem:(OMDShareItem *)item forWindow:(NSWindow *)window
{
    if (!OMDDefaultMailClientTakesMapi()) {
        [self emailShareItemWithMailtoDraft:item forWindow:window];
        return;
    }
    // MAPISendMail blocks until the client is done with the draft (or, for
    // some clients, until the compose window closes), so it runs off the
    // main thread; the result comes back to -finishMapiEmail:.
    NSMutableDictionary *request = [NSMutableDictionary dictionary];
    [request setObject:item forKey:@"item"];
    [request setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)(uintptr_t)OMDWindowHandle(window)] forKey:@"hwnd"];
    if (window != nil) {
        [request setObject:window forKey:@"window"];
    }
    [NSThread detachNewThreadSelector:@selector(sendMapiEmail:) toTarget:self withObject:request];
}

- (void)sendMapiEmail:(NSDictionary *)request
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    OMDShareItem *item = [request objectForKey:@"item"];
    ULONG status = (ULONG)-1;

    OleInitialize(NULL);
    HMODULE mapi = LoadLibraryW(L"mapi32.dll");
    OMDMAPISendMailWFunction send = mapi != NULL ? (OMDMAPISendMailWFunction)(void *)GetProcAddress(mapi, "MAPISendMailW") : NULL;
    if (send != NULL) {
        OMDMapiFileDescW file;
        memset(&file, 0, sizeof(file));
        file.nPosition = (ULONG)-1;
        file.lpszPathName = (PWSTR)OMDWideString(OMDWindowsPath([item fileURL]));
        file.lpszFileName = (PWSTR)OMDWideString([item fileName]);
        OMDMapiMessageW message;
        memset(&message, 0, sizeof(message));
        message.lpszSubject = (PWSTR)OMDWideString([item title]);
        message.nFileCount = 1;
        message.lpFiles = &file;
        ULONG_PTR parent = (ULONG_PTR)[[request objectForKey:@"hwnd"] unsignedLongLongValue];
        status = send(0, parent, &message, OMDMapiLogonUI | OMDMapiDialog, 0);
    }
    if (mapi != NULL) {
        FreeLibrary(mapi);
    }
    OleUninitialize();

    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:request];
    [result setObject:[NSNumber numberWithUnsignedLong:status] forKey:@"status"];
    [self performSelectorOnMainThread:@selector(finishMapiEmail:) withObject:result waitUntilDone:NO];
    [pool release];
}

- (void)finishMapiEmail:(NSDictionary *)result
{
    ULONG status = [[result objectForKey:@"status"] unsignedLongValue];
    if (status == OMDMapiSuccess || status == OMDMapiUserAbort) {
        return;
    }
    // No MAPI client: none installed, the new Outlook, or a browser as the
    // mailto: handler.
    NSLog(@"Share: MAPISendMailW returned %lu; falling back to a mailto: draft", (unsigned long)status);
    [self emailShareItemWithMailtoDraft:[result objectForKey:@"item"] forWindow:[result objectForKey:@"window"]];
}

- (void)showShareItemInFolder:(OMDShareItem *)item
{
    PIDLIST_ABSOLUTE list = ILCreateFromPathW(OMDWideString(OMDWindowsPath([item folderURL])));
    HRESULT result = E_FAIL;
    if (list != NULL) {
        result = SHOpenFolderAndSelectItems(list, 0, NULL, 0);
        ILFree(list);
    }
    if (FAILED(result)) {
        [super showShareItemInFolder:item];
    }
}

// CF_HDROP, so pasting attaches the file in Outlook, Teams and Explorer
// (#179); GNUstep's win32 pasteboard server passes only text and images.
- (void)copyFileOfShareItem:(OMDShareItem *)item
{
    NSString *path = [[item fileURL] path];
    if (path == nil || !OMDWindowsClipboardWriteFiles([NSArray arrayWithObject:path])) {
        [super copyFileOfShareItem:item];
    }
}

@end

id<OMDSharePresenter> OMDCreatePlatformSharePresenter(void)
{
    return [[OMDSharePresenterWindows alloc] init];
}
#endif
