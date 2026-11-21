#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <string>

namespace {

constexpr wchar_t kAppName[] = L"Lingolite";
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr int kHotKeyId = 1;
constexpr int kExitCommandId = 1001;
constexpr int kTranslateButtonId = 1002;

HINSTANCE g_instance = nullptr;
HWND g_messageWindow = nullptr;
HWND g_popupWindow = nullptr;
HWND g_sourceEdit = nullptr;
HWND g_outputEdit = nullptr;
HANDLE g_singleInstanceMutex = nullptr;
NOTIFYICONDATAW g_trayIcon{};

LRESULT CALLBACK MessageWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam);
LRESULT CALLBACK PopupWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam);

void ShowContextMenu(HWND window) {
    POINT cursor{};
    GetCursorPos(&cursor);

    HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING, kExitCommandId, L"Exit Lingolite");
    SetForegroundWindow(window);
    TrackPopupMenu(menu, TPM_RIGHTBUTTON, cursor.x, cursor.y, 0, window, nullptr);
    PostMessageW(window, WM_NULL, 0, 0);
    DestroyMenu(menu);
}

void PositionPopupNearCursor() {
    if (!g_popupWindow) {
        return;
    }

    POINT cursor{};
    GetCursorPos(&cursor);
    HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) {
        return;
    }

    RECT rect{};
    GetWindowRect(g_popupWindow, &rect);
    const int width = rect.right - rect.left;
    const int height = rect.bottom - rect.top;

    int x = cursor.x + 14;
    int y = cursor.y - height - 14;
    if (x + width > info.rcWork.right) {
        x = info.rcWork.right - width - 8;
    }
    if (y < info.rcWork.top) {
        y = cursor.y + 14;
    }
    x = std::max(x, info.rcWork.left + 8);
    y = std::max(y, info.rcWork.top + 8);

    SetWindowPos(g_popupWindow, HWND_TOPMOST, x, y, 0, 0, SWP_NOSIZE | SWP_SHOWWINDOW);
}

void ShowPopup() {
    if (!g_popupWindow) {
        return;
    }
    PositionPopupNearCursor();
    ShowWindow(g_popupWindow, SW_SHOW);
    SetForegroundWindow(g_popupWindow);
    SetFocus(g_sourceEdit);
}

void HidePopup() {
    if (g_popupWindow) {
        ShowWindow(g_popupWindow, SW_HIDE);
    }
}

void AddTrayIcon(HWND window) {
    g_trayIcon.cbSize = sizeof(g_trayIcon);
    g_trayIcon.hWnd = window;
    g_trayIcon.uID = kTrayIconId;
    g_trayIcon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    g_trayIcon.uCallbackMessage = kTrayMessage;
    g_trayIcon.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    wcscpy_s(g_trayIcon.szTip, kAppName);
    Shell_NotifyIconW(NIM_ADD, &g_trayIcon);
}

void RemoveTrayIcon() {
    Shell_NotifyIconW(NIM_DELETE, &g_trayIcon);
}

HWND CreateMessageWindow(HINSTANCE instance) {
    const wchar_t className[] = L"LingoliteMessageWindow";

    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.lpfnWndProc = MessageWindowProc;
    windowClass.hInstance = instance;
    windowClass.lpszClassName = className;
    RegisterClassExW(&windowClass);

    return CreateWindowExW(
        0,
        className,
        kAppName,
        0,
        0,
        0,
        0,
        0,
        HWND_MESSAGE,
        nullptr,
        instance,
        nullptr
    );
}

HWND CreatePopupWindow(HINSTANCE instance) {
    const wchar_t className[] = L"LingolitePopupWindow";

    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.lpfnWndProc = PopupWindowProc;
    windowClass.hInstance = instance;
    windowClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    windowClass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    windowClass.lpszClassName = className;
    RegisterClassExW(&windowClass);

    HWND window = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        className,
        kAppName,
        WS_POPUP,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        460,
        330,
        nullptr,
        nullptr,
        instance,
        nullptr
    );
    if (!window) {
        return nullptr;
    }

    g_sourceEdit = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        L"EDIT",
        L"",
        WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_AUTOVSCROLL | WS_VSCROLL,
        14,
        14,
        432,
        84,
        window,
        nullptr,
        instance,
        nullptr
    );

    g_outputEdit = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        L"EDIT",
        L"Select text and press Alt+L. HTTP integration is the next milestone.",
        WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL | WS_VSCROLL,
        14,
        110,
        432,
        160,
        window,
        nullptr,
        instance,
        nullptr
    );

    CreateWindowExW(
        0,
        L"BUTTON",
        L"Translate",
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        14,
        282,
        100,
        30,
        window,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kTranslateButtonId)),
        instance,
        nullptr
    );

    return window;
}

LRESULT CALLBACK MessageWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_HOTKEY:
        if (wParam == kHotKeyId) {
            ShowPopup();
        }
        return 0;

    case kTrayMessage:
        if (lParam == WM_LBUTTONUP) {
            ShowPopup();
        } else if (lParam == WM_RBUTTONUP) {
            ShowContextMenu(window);
        }
        return 0;

    case WM_COMMAND:
        if (LOWORD(wParam) == kExitCommandId) {
            DestroyWindow(window);
        }
        return 0;

    case WM_DESTROY:
        RemoveTrayIcon();
        UnregisterHotKey(window, kHotKeyId);
        PostQuitMessage(0);
        return 0;

    default:
        return DefWindowProcW(window, message, wParam, lParam);
    }
}

LRESULT CALLBACK PopupWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_COMMAND:
        if (LOWORD(wParam) == kTranslateButtonId) {
            SetWindowTextW(
                g_outputEdit,
                L"HTTP/UIAutomation integration is the next Windows milestone. "
                L"The macOS client is the v0.1 reference implementation."
            );
        }
        return 0;

    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) {
            HidePopup();
            return 0;
        }
        break;

    case WM_CLOSE:
        HidePopup();
        return 0;

    default:
        break;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    g_singleInstanceMutex = CreateMutexW(nullptr, TRUE, L"LingoliteSingleInstance");
    if (!g_singleInstanceMutex || GetLastError() == ERROR_ALREADY_EXISTS) {
        return 0;
    }

    g_instance = instance;
    g_messageWindow = CreateMessageWindow(instance);
    g_popupWindow = CreatePopupWindow(instance);
    if (!g_messageWindow || !g_popupWindow) {
        return 1;
    }

    AddTrayIcon(g_messageWindow);
    RegisterHotKey(g_messageWindow, kHotKeyId, MOD_ALT, 'L');

    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }

    CloseHandle(g_singleInstanceMutex);
    return static_cast<int>(message.wParam);
}

