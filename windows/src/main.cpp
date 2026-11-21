#include "app.h"
#include "resource.h"

#include <commctrl.h>
#include <shellapi.h>
#include <winrt/Windows.Foundation.h>

#include <algorithm>
#include <iterator>
#include <string>
#include <thread>
#include <vector>

HINSTANCE g_instance = nullptr;
HWND g_messageWindow = nullptr;
HWND g_popupWindow = nullptr;

namespace {

HWND g_sourceEdit = nullptr;
HWND g_outputEdit = nullptr;
HWND g_translateButton = nullptr;
HWND g_statusLabel = nullptr;
HWND g_languageCombo = nullptr;

HWND g_settingsWindow = nullptr;
HWND g_setEndpoint = nullptr;
HWND g_setModel = nullptr;
HWND g_setKey = nullptr;
HWND g_setBaiduID = nullptr;
HWND g_setBaiduKey = nullptr;
HWND g_setLLMCheck = nullptr;
HWND g_setBaiduCheck = nullptr;
HWND g_setLanguage = nullptr;

HWND g_historyWindow = nullptr;
HWND g_historyList = nullptr;

HFONT g_font = nullptr;
HFONT g_boldFont = nullptr;
NOTIFYICONDATAW g_trayIcon{};
int g_generation = 0;
bool g_translating = false;

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr int kHotkeyInput = 1;
constexpr int kHotkeySelection = 2;
constexpr int kHotkeyClipboard = 3;
constexpr int kHotkeyScreenshot = 4;
constexpr int kHotkeyOcr = 5;

enum : int {
    ID_TRANSLATE = 1001,
    ID_SOURCE = 1002,
    ID_OUTPUT = 1003,
    ID_LANGUAGE = 1004,
    ID_SETTINGS = 1005,
    ID_HISTORY = 1006,
    ID_CLOSE = 1007,

    ID_SET_ENDPOINT = 1101,
    ID_SET_MODEL = 1102,
    ID_SET_KEY = 1103,
    ID_SET_BAIDU_ID = 1104,
    ID_SET_BAIDU_KEY = 1105,
    ID_SET_LLM = 1106,
    ID_SET_BAIDU = 1107,
    ID_SET_LANGUAGE = 1108,
    ID_SET_SAVE = 1109,
    ID_SET_CANCEL = 1110,
    ID_SET_TEST_AI = 1111,
    ID_SET_TEST_BAIDU = 1112,

    ID_HISTORY_LIST = 1201,
    ID_HISTORY_COPY = 1202,
    ID_HISTORY_CLEAR = 1203,
    ID_HISTORY_CLOSE = 1204,

    ID_TRAY_INPUT = 2001,
    ID_TRAY_SELECTION = 2002,
    ID_TRAY_CLIPBOARD = 2003,
    ID_TRAY_SCREENSHOT = 2004,
    ID_TRAY_OCR = 2005,
    ID_TRAY_HISTORY = 2006,
    ID_TRAY_SETTINGS = 2007,
    ID_TRAY_EXIT = 2008,
};

const wchar_t* kLanguages[] = {
    L"自动（中英互译）",
    L"简体中文",
    L"繁體中文",
    L"English",
    L"日本語",
    L"한국어",
};

LRESULT CALLBACK MessageWindowProc(HWND, UINT, WPARAM, LPARAM);
LRESULT CALLBACK PopupWindowProc(HWND, UINT, WPARAM, LPARAM);
LRESULT CALLBACK SettingsWindowProc(HWND, UINT, WPARAM, LPARAM);
LRESULT CALLBACK HistoryWindowProc(HWND, UINT, WPARAM, LPARAM);

std::wstring GetText(HWND control) {
    const int length = GetWindowTextLengthW(control);
    if (length <= 0) {
        return {};
    }
    std::wstring text(static_cast<size_t>(length) + 1, L'\0');
    const int copied = GetWindowTextW(control, text.data(), length + 1);
    text.resize(copied > 0 ? copied : 0);
    return text;
}

std::wstring Trim(std::wstring value) {
    while (!value.empty() && (value.back() == L' ' || value.back() == L'\r' || value.back() == L'\n')) {
        value.pop_back();
    }
    size_t start = 0;
    while (start < value.size() && (value[start] == L' ' || value[start] == L'\r' || value[start] == L'\n')) {
        ++start;
    }
    return value.substr(start);
}

void ApplyFont(HWND parent, HFONT font) {
    EnumChildWindows(
        parent,
        [](HWND child, LPARAM value) -> BOOL {
            SendMessageW(child, WM_SETFONT, static_cast<WPARAM>(value), TRUE);
            return TRUE;
        },
        reinterpret_cast<LPARAM>(font)
    );
}

void CenterWindow(HWND window, int width, int height, int offsetY = 0) {
    RECT work{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    const int x = work.left + (work.right - work.left - width) / 2;
    const int y = work.top + (work.bottom - work.top - height) / 2 + offsetY;
    SetWindowPos(window, HWND_TOPMOST, x, y, width, height, SWP_SHOWWINDOW);
}

void PopulateLanguages(HWND combo) {
    SendMessageW(combo, CB_RESETCONTENT, 0, 0);
    for (const auto* language : kLanguages) {
        SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(language));
    }

    int index = 0;
    for (int i = 0; i < static_cast<int>(std::size(kLanguages)); ++i) {
        if (Config().targetLanguage == kLanguages[i]) {
            index = i;
            break;
        }
    }
    SendMessageW(combo, CB_SETCURSEL, index, 0);
}

std::wstring SelectedLanguage(HWND combo) {
    const int index = static_cast<int>(SendMessageW(combo, CB_GETCURSEL, 0, 0));
    if (index >= 0 && index < static_cast<int>(std::size(kLanguages))) {
        return kLanguages[index];
    }
    return L"简体中文";
}

void UpdateStatus() {
    if (!g_statusLabel) {
        return;
    }
    if (g_translating) {
        SetWindowTextW(g_statusLabel, L"正在翻译…");
        return;
    }
    const std::wstring text = Trim(GetText(g_sourceEdit));
    const std::wstring status = std::to_wstring(text.size()) + L" 字符";
    SetWindowTextW(g_statusLabel, status.c_str());
}

void ShowTranslationResult(HWND output, const std::vector<ServiceResult>& results) {
    std::wstring text;
    for (const auto& result : results) {
        if (!text.empty()) {
            text += L"\r\n\r\n";
        }
        text += result.title;
        text += L"\r\n";
        text += result.text;
    }
    SetWindowTextW(output, text.c_str());
}

void StartTranslation(const std::wstring& source) {
    if (!g_popupWindow || source.empty()) {
        return;
    }

    ++g_generation;
    const int generation = g_generation;
    g_translating = true;
    SetWindowTextW(g_outputEdit, L"翻译中…");
    SetWindowTextW(g_statusLabel, L"正在翻译…");
    EnableWindow(g_translateButton, FALSE);

    const AppConfig config = Config();
    const std::wstring target = ResolveTargetLanguage(source);

    std::thread([source, generation, config, target]() {
        try {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
        } catch (...) {
        }

        std::vector<ServiceResult> results;

        if (config.llmEnabled) {
            std::wstring output;
            std::wstring error;
            const std::wstring title = L"AI 翻译 · " + config.model;
            if (TranslateAI(config, source, output, error)) {
                results.push_back({title, output, true});
            } else {
                results.push_back({title, error, false});
            }
        }

        if (config.baiduEnabled) {
            std::wstring output;
            std::wstring error;
            if (TranslateBaidu(config, source, output, error)) {
                results.push_back({L"百度翻译", output, true});
            } else {
                results.push_back({L"百度翻译", error, false});
            }
        }

        if (results.empty()) {
            results.push_back({
                L"翻译服务",
                L"还没有启用翻译服务，请在设置中开启 AI 翻译或百度翻译。",
                false,
            });
        }

        auto* payload = new TranslationPayload{
            generation,
            source,
            target,
            std::move(results),
        };

        if (g_popupWindow) {
            PostMessageW(
                g_popupWindow,
                WM_APP_TRANSLATE_DONE,
                0,
                reinterpret_cast<LPARAM>(payload)
            );
        } else {
            delete payload;
        }

        try {
            winrt::uninit_apartment();
        } catch (...) {
        }
    }).detach();
}

void AddTrayIcon() {
    g_trayIcon.cbSize = sizeof(g_trayIcon);
    g_trayIcon.hWnd = g_messageWindow;
    g_trayIcon.uID = 1;
    g_trayIcon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    g_trayIcon.uCallbackMessage = kTrayMessage;
    g_trayIcon.hIcon = LoadIconW(g_instance, MAKEINTRESOURCEW(IDI_APP_ICON));
    if (!g_trayIcon.hIcon) {
        g_trayIcon.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    }
    wcscpy_s(g_trayIcon.szTip, L"Lingolite · Alt+D 选中翻译");
    Shell_NotifyIconW(NIM_ADD, &g_trayIcon);
}

void RemoveTrayIcon() {
    Shell_NotifyIconW(NIM_DELETE, &g_trayIcon);
}

void ShowBalloon(const std::wstring& message) {
    NOTIFYICONDATAW data = g_trayIcon;
    data.uFlags = NIF_INFO;
    data.dwInfoFlags = NIIF_INFO;
    wcscpy_s(data.szInfoTitle, L"Lingolite");
    wcsncpy_s(data.szInfo, message.c_str(), _TRUNCATE);
    Shell_NotifyIconW(NIM_MODIFY, &data);
}

void HidePopup() {
    if (g_popupWindow) {
        ShowWindow(g_popupWindow, SW_HIDE);
    }
}

void ShowPopup(const std::wstring& text, bool translate) {
    if (!g_popupWindow) {
        return;
    }

    g_generation++;
    g_translating = false;
    EnableWindow(g_translateButton, TRUE);
    SetWindowTextW(g_sourceEdit, text.c_str());
    SetWindowTextW(g_outputEdit, L"");
    PopulateLanguages(g_languageCombo);
    UpdateStatus();

    CenterWindow(g_popupWindow, 540, 470, -30);
    SetForegroundWindow(g_popupWindow);
    SetFocus(g_sourceEdit);

    if (translate && !Trim(text).empty()) {
        StartTranslation(Trim(text));
    }
}

void ShowContextMenu() {
    POINT cursor{};
    GetCursorPos(&cursor);

    HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING, ID_TRAY_INPUT, L"输入翻译\tAlt+A");
    AppendMenuW(menu, MF_STRING, ID_TRAY_SELECTION, L"选中翻译\tAlt+D");
    AppendMenuW(menu, MF_STRING, ID_TRAY_CLIPBOARD, L"剪贴翻译\tAlt+V");
    AppendMenuW(menu, MF_STRING, ID_TRAY_SCREENSHOT, L"截图翻译\tAlt+S");
    AppendMenuW(menu, MF_STRING, ID_TRAY_OCR, L"截图 OCR（复制）\tShift+Alt+S");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, ID_TRAY_HISTORY, L"历史记录");
    AppendMenuW(menu, MF_STRING, ID_TRAY_SETTINGS, L"设置");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, ID_TRAY_EXIT, L"退出 Lingolite");

    SetForegroundWindow(g_messageWindow);
    TrackPopupMenu(menu, TPM_RIGHTBUTTON, cursor.x, cursor.y, 0, g_messageWindow, nullptr);
    PostMessageW(g_messageWindow, WM_NULL, 0, 0);
    DestroyMenu(menu);
}

void CopyHistoryEntry(int index) {
    if (index < 0 || index >= static_cast<int>(History().size())) {
        return;
    }
    const auto& entry = History()[index];
    if (entry.results.empty()) {
        return;
    }
    SetClipboardText(entry.results.front().text);
    ShowBalloon(L"已复制历史译文");
}

void RefreshHistoryWindow() {
    if (!g_historyList) {
        return;
    }
    SendMessageW(g_historyList, LB_RESETCONTENT, 0, 0);
    for (const auto& entry : History()) {
        std::wstring line = L"[" + entry.time + L"]  " + entry.source;
        if (!entry.results.empty()) {
            line += L"  →  " + entry.results.front().text;
        }
        std::replace(line.begin(), line.end(), L'\r', L' ');
        std::replace(line.begin(), line.end(), L'\n', L' ');
        if (line.size() > 140) {
            line = line.substr(0, 140) + L"…";
        }
        SendMessageW(
            g_historyList,
            LB_ADDSTRING,
            0,
            reinterpret_cast<LPARAM>(line.c_str())
        );
    }
}

void ShowHistoryWindow() {
    if (!g_historyWindow) {
        return;
    }
    RefreshHistoryWindow();
    CenterWindow(g_historyWindow, 620, 460);
    SetForegroundWindow(g_historyWindow);
}

void ShowSettingsWindow() {
    if (!g_settingsWindow) {
        return;
    }

    SetWindowTextW(g_setEndpoint, Config().endpoint.c_str());
    SetWindowTextW(g_setModel, Config().model.c_str());
    SetWindowTextW(g_setKey, Config().aiKey.c_str());
    SetWindowTextW(g_setBaiduID, Config().baiduAppID.c_str());
    SetWindowTextW(g_setBaiduKey, Config().baiduKey.c_str());
    SendMessageW(
        g_setLLMCheck,
        BM_SETCHECK,
        Config().llmEnabled ? BST_CHECKED : BST_UNCHECKED,
        0
    );
    SendMessageW(
        g_setBaiduCheck,
        BM_SETCHECK,
        Config().baiduEnabled ? BST_CHECKED : BST_UNCHECKED,
        0
    );

    SendMessageW(g_setLanguage, CB_RESETCONTENT, 0, 0);
    for (const auto* language : kLanguages) {
        SendMessageW(g_setLanguage, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(language));
    }
    int index = 0;
    for (int i = 0; i < static_cast<int>(std::size(kLanguages)); ++i) {
        if (Config().targetLanguage == kLanguages[i]) {
            index = i;
            break;
        }
    }
    SendMessageW(g_setLanguage, CB_SETCURSEL, index, 0);

    CenterWindow(g_settingsWindow, 640, 520);
    SetForegroundWindow(g_settingsWindow);
}

void ReadSettings(AppConfig& config) {
    config.endpoint = Trim(GetText(g_setEndpoint));
    config.model = Trim(GetText(g_setModel));
    config.aiKey = Trim(GetText(g_setKey));
    config.baiduAppID = Trim(GetText(g_setBaiduID));
    config.baiduKey = Trim(GetText(g_setBaiduKey));
    config.llmEnabled = SendMessageW(g_setLLMCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
    config.baiduEnabled = SendMessageW(g_setBaiduCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
    config.targetLanguage = SelectedLanguage(g_setLanguage);
}

void TestService(bool baidu) {
    AppConfig config = Config();
    ReadSettings(config);

    std::thread([config, baidu]() {
        try {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
        } catch (...) {
        }
        std::wstring output;
        std::wstring error;
        const bool ok = baidu
            ? TranslateBaidu(config, L"Hello", output, error)
            : TranslateAI(config, L"Hello", output, error);
        const std::wstring message = ok
            ? L"连接成功：\r\n" + output
            : L"连接失败：\r\n" + error;
        MessageBoxW(nullptr, message.c_str(), L"Lingolite 测试", MB_OK | MB_ICONINFORMATION);
        try {
            winrt::uninit_apartment();
        } catch (...) {
        }
    }).detach();
}

LRESULT CALLBACK SourceEditProc(
    HWND edit,
    UINT message,
    WPARAM wParam,
    LPARAM lParam,
    UINT_PTR,
    DWORD_PTR
) {
    if (message == WM_KEYDOWN) {
        if (wParam == VK_RETURN) {
            const bool modified =
                (GetKeyState(VK_CONTROL) & 0x8000) != 0
                || (GetKeyState(VK_SHIFT) & 0x8000) != 0
                || (GetKeyState(VK_MENU) & 0x8000) != 0;
            if (modified) {
                SendMessageW(edit, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(L"\r\n"));
                return 0;
            }
            PostMessageW(
                GetParent(edit),
                WM_COMMAND,
                MAKEWPARAM(ID_TRANSLATE, BN_CLICKED),
                0
            );
            return 0;
        }
        if (wParam == VK_ESCAPE) {
            PostMessageW(GetParent(edit), WM_CLOSE, 0, 0);
            return 0;
        }
    }
    return DefSubclassProc(edit, message, wParam, lParam);
}

HWND CreateControl(
    LPCWSTR className,
    LPCWSTR text,
    DWORD style,
    int x,
    int y,
    int width,
    int height,
    HWND parent,
    int id,
    DWORD exStyle = 0
) {
    return CreateWindowExW(
        exStyle,
        className,
        text,
        style,
        x,
        y,
        width,
        height,
        parent,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
        g_instance,
        nullptr
    );
}

LRESULT CALLBACK PopupWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_CREATE: {
        const int titleX = 16;
        CreateControl(
            L"STATIC", L"Lingolite",
            WS_CHILD | WS_VISIBLE,
            titleX, 12, 160, 24, window, -1
        );
        g_languageCombo = CreateControl(
            WC_COMBOBOXW, L"",
            WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
            300, 10, 110, 160, window, ID_LANGUAGE
        );
        CreateControl(
            L"BUTTON", L"历史",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            418, 10, 50, 26, window, ID_HISTORY
        );
        CreateControl(
            L"BUTTON", L"设置",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            472, 10, 50, 26, window, ID_SETTINGS
        );
        CreateControl(
            L"BUTTON", L"×",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            526, 10, 24, 26, window, ID_CLOSE
        );

        CreateControl(
            L"STATIC", L"原文",
            WS_CHILD | WS_VISIBLE,
            16, 48, 80, 20, window, -1
        );
        g_sourceEdit = CreateControl(
            L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_VSCROLL,
            16, 68, 508, 92, window, ID_SOURCE,
            WS_EX_CLIENTEDGE
        );
        g_translateButton = CreateControl(
            L"BUTTON", L"翻译",
            WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
            16, 168, 90, 30, window, ID_TRANSLATE
        );
        g_statusLabel = CreateControl(
            L"STATIC", L"就绪",
            WS_CHILD | WS_VISIBLE,
            116, 174, 300, 20, window, -1
        );

        CreateControl(
            L"STATIC", L"译文",
            WS_CHILD | WS_VISIBLE,
            16, 206, 80, 20, window, -1
        );
        g_outputEdit = CreateControl(
            L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL | WS_VSCROLL,
            16, 226, 508, 206, window, ID_OUTPUT,
            WS_EX_CLIENTEDGE
        );

        ApplyFont(window, g_font);
        SendMessageW(g_translateButton, WM_SETFONT, reinterpret_cast<WPARAM>(g_boldFont), TRUE);
        SendMessageW(g_sourceEdit, WM_SETFONT, reinterpret_cast<WPARAM>(g_font), TRUE);
        SendMessageW(g_outputEdit, WM_SETFONT, reinterpret_cast<WPARAM>(g_font), TRUE);
        SetWindowSubclass(g_sourceEdit, SourceEditProc, 1, 0);

        PopulateLanguages(g_languageCombo);
        return 0;
    }

    case WM_COMMAND: {
        const int id = LOWORD(wParam);
        const int notification = HIWORD(wParam);
        if (id == ID_TRANSLATE && notification == BN_CLICKED) {
            const std::wstring text = Trim(GetText(g_sourceEdit));
            if (text.empty()) {
                SetFocus(g_sourceEdit);
            } else {
                StartTranslation(text);
            }
            return 0;
        }
        if (id == ID_LANGUAGE && notification == CBN_SELCHANGE) {
            Config().targetLanguage = SelectedLanguage(g_languageCombo);
            SaveConfig();
            return 0;
        }
        if (id == ID_SOURCE && notification == EN_CHANGE) {
            UpdateStatus();
            return 0;
        }
        if (id == ID_SETTINGS) {
            ShowSettingsWindow();
            return 0;
        }
        if (id == ID_HISTORY) {
            ShowHistoryWindow();
            return 0;
        }
        if (id == ID_CLOSE) {
            HidePopup();
            return 0;
        }
        break;
    }

    case WM_APP_TRANSLATE_DONE: {
        auto* payload = reinterpret_cast<TranslationPayload*>(lParam);
        if (!payload) {
            return 0;
        }
        if (payload->generation == g_generation) {
            ShowTranslationResult(g_outputEdit, payload->results);
            g_translating = false;
            EnableWindow(g_translateButton, TRUE);
            UpdateStatus();
            AddHistory(payload->source, payload->target, payload->results);
        }
        delete payload;
        return 0;
    }

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

HWND CreatePopup(HINSTANCE instance) {
    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.lpfnWndProc = PopupWindowProc;
    windowClass.hInstance = instance;
    windowClass.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(IDI_APP_ICON));
    windowClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    windowClass.hbrBackground = CreateSolidBrush(RGB(246, 246, 248));
    windowClass.lpszClassName = L"LingolitePopup";
    RegisterClassExW(&windowClass);

    return CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        L"LingolitePopup",
        L"Lingolite",
        WS_POPUP,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        540,
        520,
        nullptr,
        nullptr,
        instance,
        nullptr
    );
}

LRESULT CALLBACK SettingsWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_CREATE: {
        int y = 16;
        CreateControl(
            L"STATIC", L"AI 翻译（OpenAI 兼容）",
            WS_CHILD | WS_VISIBLE,
            20, y, 300, 22, window, -1
        );
        SendMessageW(GetWindow(window, GW_CHILD), WM_SETFONT, reinterpret_cast<WPARAM>(g_boldFont), TRUE);

        y += 30;
        g_setLLMCheck = CreateControl(
            L"BUTTON", L"启用 AI 翻译",
            WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
            20, y, 180, 24, window, ID_SET_LLM
        );

        y += 32;
        CreateControl(L"STATIC", L"接口地址", WS_CHILD | WS_VISIBLE, 20, y + 4, 80, 20, window, -1);
        g_setEndpoint = CreateControl(
            L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
            110, y, 500, 26, window, ID_SET_ENDPOINT,
            WS_EX_CLIENTEDGE
        );

        y += 36;
        CreateControl(L"STATIC", L"模型", WS_CHILD | WS_VISIBLE, 20, y + 4, 80, 20, window, -1);
        g_setModel = CreateControl(
            L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
            110, y, 500, 26, window, ID_SET_MODEL,
            WS_EX_CLIENTEDGE
        );

        y += 36;
        CreateControl(L"STATIC", L"API Key", WS_CHILD | WS_VISIBLE, 20, y + 4, 80, 20, window, -1);
        g_setKey = CreateControl(
            L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL | ES_PASSWORD,
            110, y, 500, 26, window, ID_SET_KEY,
            WS_EX_CLIENTEDGE
        );

        y += 36;
        CreateControl(L"STATIC", L"目标语言", WS_CHILD | WS_VISIBLE, 20, y + 4, 80, 20, window, -1);
        g_setLanguage = CreateControl(
            WC_COMBOBOXW, L"",
            WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
            110, y, 220, 160, window, ID_SET_LANGUAGE
        );

        y += 44;
        CreateControl(
            L"STATIC", L"百度翻译",
            WS_CHILD | WS_VISIBLE,
            20, y, 300, 22, window, -1
        );

        y += 30;
        g_setBaiduCheck = CreateControl(
            L"BUTTON", L"启用百度翻译",
            WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
            20, y, 180, 24, window, ID_SET_BAIDU
        );

        y += 32;
        CreateControl(L"STATIC", L"AppID", WS_CHILD | WS_VISIBLE, 20, y + 4, 80, 20, window, -1);
        g_setBaiduID = CreateControl(
            L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
            110, y, 500, 26, window, ID_SET_BAIDU_ID,
            WS_EX_CLIENTEDGE
        );

        y += 36;
        CreateControl(L"STATIC", L"密钥", WS_CHILD | WS_VISIBLE, 20, y + 4, 80, 20, window, -1);
        g_setBaiduKey = CreateControl(
            L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL | ES_PASSWORD,
            110, y, 500, 26, window, ID_SET_BAIDU_KEY,
            WS_EX_CLIENTEDGE
        );

        CreateControl(
            L"STATIC", L"密钥保存在 Windows 凭据管理器；接口支持 OpenAI 兼容服务。",
            WS_CHILD | WS_VISIBLE,
            20, y + 40, 520, 20, window, -1
        );

        CreateControl(
            L"BUTTON", L"测试 AI",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            20, y + 72, 100, 30, window, ID_SET_TEST_AI
        );
        CreateControl(
            L"BUTTON", L"测试百度",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            128, y + 72, 100, 30, window, ID_SET_TEST_BAIDU
        );
        CreateControl(
            L"BUTTON", L"保存",
            WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
            420, y + 72, 90, 30, window, ID_SET_SAVE
        );
        CreateControl(
            L"BUTTON", L"取消",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            520, y + 72, 90, 30, window, ID_SET_CANCEL
        );

        ApplyFont(window, g_font);
        return 0;
    }

    case WM_COMMAND: {
        const int id = LOWORD(wParam);
        if (id == ID_SET_SAVE) {
            AppConfig config = Config();
            ReadSettings(config);
            Config() = config;
            SaveConfig();
            PopulateLanguages(g_languageCombo);
            ShowWindow(window, SW_HIDE);
            return 0;
        }
        if (id == ID_SET_CANCEL) {
            ShowWindow(window, SW_HIDE);
            return 0;
        }
        if (id == ID_SET_TEST_AI) {
            TestService(false);
            return 0;
        }
        if (id == ID_SET_TEST_BAIDU) {
            TestService(true);
            return 0;
        }
        break;
    }

    case WM_CLOSE:
        ShowWindow(window, SW_HIDE);
        return 0;

    default:
        break;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

HWND CreateSettings(HINSTANCE instance) {
    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.lpfnWndProc = SettingsWindowProc;
    windowClass.hInstance = instance;
    windowClass.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(IDI_APP_ICON));
    windowClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    windowClass.hbrBackground = CreateSolidBrush(RGB(250, 250, 252));
    windowClass.lpszClassName = L"LingoliteSettings";
    RegisterClassExW(&windowClass);

    return CreateWindowExW(
        WS_EX_DLGMODALFRAME | WS_EX_TOOLWINDOW,
        L"LingoliteSettings",
        L"Lingolite 设置",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        640,
        470,
        nullptr,
        nullptr,
        instance,
        nullptr
    );
}

LRESULT CALLBACK HistoryWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_CREATE:
        g_historyList = CreateControl(
            L"LISTBOX", L"",
            WS_CHILD | WS_VISIBLE | WS_BORDER | WS_VSCROLL | LBS_NOTIFY,
            12, 12, 576, 360, window, ID_HISTORY_LIST
        );
        CreateControl(
            L"BUTTON", L"复制译文",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            12, 388, 100, 30, window, ID_HISTORY_COPY
        );
        CreateControl(
            L"BUTTON", L"清空",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            120, 388, 90, 30, window, ID_HISTORY_CLEAR
        );
        CreateControl(
            L"BUTTON", L"关闭",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            506, 388, 80, 30, window, ID_HISTORY_CLOSE
        );
        ApplyFont(window, g_font);
        return 0;

    case WM_COMMAND: {
        const int id = LOWORD(wParam);
        if (id == ID_HISTORY_LIST && HIWORD(wParam) == LBN_DBLCLK) {
            const int index = static_cast<int>(SendMessageW(g_historyList, LB_GETCURSEL, 0, 0));
            CopyHistoryEntry(index);
            return 0;
        }
        if (id == ID_HISTORY_COPY) {
            const int index = static_cast<int>(SendMessageW(g_historyList, LB_GETCURSEL, 0, 0));
            CopyHistoryEntry(index);
            return 0;
        }
        if (id == ID_HISTORY_CLEAR) {
            if (MessageBoxW(
                    window,
                    L"清空全部历史记录？此操作不可撤销。",
                    L"Lingolite",
                    MB_YESNO | MB_ICONQUESTION) == IDYES) {
                History().clear();
                SaveHistory();
                RefreshHistoryWindow();
            }
            return 0;
        }
        if (id == ID_HISTORY_CLOSE) {
            ShowWindow(window, SW_HIDE);
            return 0;
        }
        break;
    }

    case WM_CLOSE:
        ShowWindow(window, SW_HIDE);
        return 0;

    default:
        break;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

HWND CreateHistory(HINSTANCE instance) {
    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.lpfnWndProc = HistoryWindowProc;
    windowClass.hInstance = instance;
    windowClass.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(IDI_APP_ICON));
    windowClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    windowClass.hbrBackground = CreateSolidBrush(RGB(250, 250, 252));
    windowClass.lpszClassName = L"LingoliteHistory";
    RegisterClassExW(&windowClass);

    return CreateWindowExW(
        WS_EX_DLGMODALFRAME | WS_EX_TOOLWINDOW,
        L"LingoliteHistory",
        L"Lingolite 历史记录",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        620,
        460,
        nullptr,
        nullptr,
        instance,
        nullptr
    );
}

void HandleSelection() {
    const std::wstring text = Trim(ReadSelectedText());
    if (text.empty()) {
        ShowBalloon(L"没有获取到选中文本");
        ShowPopup(L"", false);
        return;
    }
    ShowPopup(text, true);
}

void HandleClipboard() {
    const std::wstring text = Trim(GetClipboardText());
    if (text.empty()) {
        ShowBalloon(L"剪贴板里没有可翻译的文本");
        return;
    }
    ShowPopup(text, true);
}

LRESULT CALLBACK MessageWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_HOTKEY:
        switch (wParam) {
        case kHotkeyInput:
            ShowPopup(L"", false);
            break;
        case kHotkeySelection:
            HandleSelection();
            break;
        case kHotkeyClipboard:
            HandleClipboard();
            break;
        case kHotkeyScreenshot:
            StartScreenshotSelection(window, true);
            break;
        case kHotkeyOcr:
            StartScreenshotSelection(window, false);
            break;
        default:
            break;
        }
        return 0;

    case kTrayMessage:
        if (LOWORD(lParam) == WM_LBUTTONUP) {
            ShowPopup(L"", false);
        } else if (LOWORD(lParam) == WM_RBUTTONUP) {
            ShowContextMenu();
        }
        return 0;

    case WM_APP_OCR_DONE: {
        auto* payload = reinterpret_cast<OcrPayload*>(lParam);
        if (!payload) {
            return 0;
        }
        if (Trim(payload->text).empty()) {
            ShowBalloon(L"没有识别到文字，请换一个区域再试");
        } else if (payload->translate) {
            ShowPopup(payload->text, true);
        } else {
            SetClipboardText(payload->text);
            ShowBalloon(
                L"已复制 " + std::to_wstring(payload->text.size()) + L" 个字符"
            );
        }
        delete payload;
        return 0;
    }

    case WM_COMMAND:
        switch (LOWORD(wParam)) {
        case ID_TRAY_INPUT:
            ShowPopup(L"", false);
            break;
        case ID_TRAY_SELECTION:
            HandleSelection();
            break;
        case ID_TRAY_CLIPBOARD:
            HandleClipboard();
            break;
        case ID_TRAY_SCREENSHOT:
            StartScreenshotSelection(window, true);
            break;
        case ID_TRAY_OCR:
            StartScreenshotSelection(window, false);
            break;
        case ID_TRAY_HISTORY:
            ShowHistoryWindow();
            break;
        case ID_TRAY_SETTINGS:
            ShowSettingsWindow();
            break;
        case ID_TRAY_EXIT:
            DestroyWindow(window);
            break;
        default:
            break;
        }
        return 0;

    case WM_DESTROY:
        RemoveTrayIcon();
        UnregisterHotKey(window, kHotkeyInput);
        UnregisterHotKey(window, kHotkeySelection);
        UnregisterHotKey(window, kHotkeyClipboard);
        UnregisterHotKey(window, kHotkeyScreenshot);
        UnregisterHotKey(window, kHotkeyOcr);
        SaveConfig();
        SaveHistory();
        PostQuitMessage(0);
        return 0;

    default:
        break;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

HWND CreateMessageWindow(HINSTANCE instance) {
    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.lpfnWndProc = MessageWindowProc;
    windowClass.hInstance = instance;
    windowClass.lpszClassName = L"LingoliteMessage";
    RegisterClassExW(&windowClass);

    return CreateWindowExW(
        0,
        L"LingoliteMessage",
        L"",
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

}  // namespace

void RefreshHistoryList() {
    RefreshHistoryWindow();
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_SYSTEM_AWARE);

    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
    } catch (...) {
    }

    HANDLE mutex = CreateMutexW(nullptr, TRUE, L"LingoliteSingleInstance");
    if (!mutex || GetLastError() == ERROR_ALREADY_EXISTS) {
        return 0;
    }

    g_instance = instance;
    g_font = CreateFontW(
        -12, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI"
    );
    g_boldFont = CreateFontW(
        -13, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI"
    );

    LoadConfig();
    LoadHistory();

    g_messageWindow = CreateMessageWindow(instance);
    g_popupWindow = CreatePopup(instance);
    g_settingsWindow = CreateSettings(instance);
    g_historyWindow = CreateHistory(instance);
    if (!g_messageWindow || !g_popupWindow || !g_settingsWindow || !g_historyWindow) {
        return 1;
    }

    AddTrayIcon();

    struct Hotkey {
        int id;
        UINT modifiers;
        UINT key;
        const wchar_t* name;
    };
    const Hotkey hotkeys[] = {
        {kHotkeyInput, MOD_ALT, 'A', L"Alt+A"},
        {kHotkeySelection, MOD_ALT, 'D', L"Alt+D"},
        {kHotkeyClipboard, MOD_ALT, 'V', L"Alt+V"},
        {kHotkeyScreenshot, MOD_ALT, 'S', L"Alt+S"},
        {kHotkeyOcr, MOD_ALT | MOD_SHIFT, 'S', L"Shift+Alt+S"},
    };

    std::wstring failed;
    for (const auto& hotkey : hotkeys) {
        if (!RegisterHotKey(g_messageWindow, hotkey.id, hotkey.modifiers, hotkey.key)) {
            if (!failed.empty()) {
                failed += L"、";
            }
            failed += hotkey.name;
        }
    }
    if (!failed.empty()) {
        const std::wstring message =
            failed + L" 已被其他应用占用。可以退出冲突应用，或稍后在其他版本中自定义。";
        MessageBoxW(nullptr, message.c_str(), L"Lingolite", MB_OK | MB_ICONWARNING);
    }

    if (Config().aiKey.empty() && Config().baiduKey.empty()) {
        ShowBalloon(L"请在托盘菜单 → 设置中配置翻译服务");
    }

    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }

    RemoveTrayIcon();
    CloseHandle(mutex);
    DeleteObject(g_font);
    DeleteObject(g_boldFont);
    try {
        winrt::uninit_apartment();
    } catch (...) {
    }
    return static_cast<int>(message.wParam);
}
