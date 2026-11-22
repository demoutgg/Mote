#include "app.h"
#include "resource.h"

#include <commctrl.h>
#include <shellapi.h>
#include <winrt/Windows.Foundation.h>

#include <algorithm>
#include <cstdlib>
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
HWND g_setLaunchCheck = nullptr;

HWND g_settingsTab = nullptr;
HWND g_setPrompt = nullptr;
HWND g_setAutoCopyCheck = nullptr;
HWND g_setPreset = nullptr;
HWND g_setModelCombo = nullptr;
HWND g_setFetchModels = nullptr;
HWND g_setPopupWidth = nullptr;
HWND g_setPopupHeight = nullptr;
HWND g_hotkeyButtons[5] = {};
int g_recordingHotkey = 0;

HWND g_historyWindow = nullptr;
HWND g_historyList = nullptr;
HWND g_historySearch = nullptr;
std::wstring g_historyFilter;
std::vector<int> g_historyVisible;   // 过滤后列表行对应的 History 下标

HWND g_popupClose = nullptr;
HWND g_popupHistory = nullptr;
HWND g_popupSettings = nullptr;
HWND g_popupTitle = nullptr;
HWND g_popupSourceLabel = nullptr;
HWND g_popupOutputLabel = nullptr;
bool g_suppressAutoHide = false;

// 设置页四个分页共用一个窗口，控件建好后按页显隐
std::vector<HWND> g_pageControls[4];

HFONT g_font = nullptr;
HFONT g_boldFont = nullptr;
NOTIFYICONDATAW g_trayIcon{};
int g_generation = 0;
bool g_translating = false;

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT WM_APP_MODEL_LIST = WM_APP + 20;
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
    ID_SET_LAUNCH = 1113,
    ID_SET_TAB = 1114,
    ID_SET_PROMPT = 1115,
    ID_SET_PROMPT_RESET = 1116,
    ID_SET_AUTOCOPY = 1117,
    ID_SET_PRESET = 1118,
    ID_SET_FETCH_MODELS = 1119,
    ID_SET_POPUP_WIDTH = 1120,
    ID_SET_POPUP_HEIGHT = 1121,
    ID_SET_HOTKEY_BASE = 1130,   // 1130..1134 对应五个动作的录制按钮
    ID_SET_OPEN_HISTORY = 1140,
    ID_SET_CLEAR_HISTORY = 1141,

    ID_TRAY_ABOUT = 1210,

    ID_HISTORY_LIST = 1201,
    ID_HISTORY_COPY = 1202,
    ID_HISTORY_COPY_SOURCE = 1205,
    ID_HISTORY_SEARCH = 1206,
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
HWND CreateSettings(HINSTANCE instance);
HWND CreateHistory(HINSTANCE instance);

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


// 热键按 "Ctrl+Alt+K" 这样的文本存配置，注册时再解析；解析和注册失败的项会汇总提示。
struct HotkeySpec {
    UINT modifiers = 0;
    UINT key = 0;
};

const int kHotkeyIds[] = {
    kHotkeyInput,
    kHotkeySelection,
    kHotkeyClipboard,
    kHotkeyScreenshot,
    kHotkeyOcr,
};

const wchar_t* HotkeyLabel(int id) {
    switch (id) {
    case kHotkeySelection: return L"选中翻译";
    case kHotkeyClipboard: return L"剪贴翻译";
    case kHotkeyScreenshot: return L"截图翻译";
    case kHotkeyOcr: return L"截图 OCR";
    default: return L"输入翻译";
    }
}

std::wstring& HotkeyText(AppConfig& config, int id) {
    switch (id) {
    case kHotkeySelection: return config.hotkeySelection;
    case kHotkeyClipboard: return config.hotkeyClipboard;
    case kHotkeyScreenshot: return config.hotkeyScreenshot;
    case kHotkeyOcr: return config.hotkeyOcr;
    default: return config.hotkeyInput;
    }
}

bool ParseHotkey(const std::wstring& text, HotkeySpec& spec) {
    spec = {};
    size_t start = 0;
    while (start <= text.size()) {
        const size_t plus = text.find(L'+', start);
        const std::wstring token = Trim(text.substr(
            start,
            plus == std::wstring::npos ? std::wstring::npos : plus - start
        ));
        if (!token.empty()) {
            if (_wcsicmp(token.c_str(), L"Ctrl") == 0 || _wcsicmp(token.c_str(), L"Control") == 0) {
                spec.modifiers |= MOD_CONTROL;
            } else if (_wcsicmp(token.c_str(), L"Alt") == 0) {
                spec.modifiers |= MOD_ALT;
            } else if (_wcsicmp(token.c_str(), L"Shift") == 0) {
                spec.modifiers |= MOD_SHIFT;
            } else if (_wcsicmp(token.c_str(), L"Win") == 0) {
                spec.modifiers |= MOD_WIN;
            } else if (token.size() == 1) {
                wchar_t ch = token[0];
                if (ch >= L'a' && ch <= L'z') {
                    ch = static_cast<wchar_t>(ch - L'a' + L'A');
                }
                if ((ch >= L'A' && ch <= L'Z') || (ch >= L'0' && ch <= L'9')) {
                    spec.key = static_cast<UINT>(ch);
                } else {
                    return false;
                }
            } else if (token.size() == 2 && (token[0] == L'F' || token[0] == L'f')
                       && token[1] >= L'1' && token[1] <= L'9') {
                spec.key = VK_F1 + static_cast<UINT>(token[1] - L'1');
            } else {
                return false;
            }
        }
        if (plus == std::wstring::npos) {
            break;
        }
        start = plus + 1;
    }
    return spec.key != 0 && spec.modifiers != 0;
}

std::wstring FormatHotkey(UINT modifiers, UINT key) {
    std::wstring text;
    if (modifiers & MOD_CONTROL) text += L"Ctrl+";
    if (modifiers & MOD_ALT) text += L"Alt+";
    if (modifiers & MOD_SHIFT) text += L"Shift+";
    if (modifiers & MOD_WIN) text += L"Win+";
    if (key >= VK_F1 && key <= VK_F9) {
        text += L"F" + std::to_wstring(key - VK_F1 + 1);
    } else if (key >= L'A' && key <= L'Z') {
        text += static_cast<wchar_t>(key);
    } else {
        text += static_cast<wchar_t>(key);
    }
    return text;
}

// 返回空串表示可以接受，否则是要提示给用户的原因
std::wstring HotkeyRejection(UINT modifiers, UINT key) {
    if (modifiers == 0) {
        return L"快捷键至少要带一个修饰键（Ctrl / Alt / Shift / Win）。";
    }
    if ((modifiers & (MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_WIN)) == 0) {
        return L"快捷键至少要带一个修饰键（Ctrl / Alt / Shift / Win）。";
    }
    if (key == VK_F4 && (modifiers & MOD_ALT)) {
        return L"Alt+F4 是关闭窗口的系统快捷键。";
    }
    if (key == VK_TAB && (modifiers & MOD_ALT)) {
        return L"Alt+Tab 是切换窗口的系统快捷键。";
    }
    if (key == VK_ESCAPE && (modifiers & MOD_CONTROL)) {
        return L"Ctrl+Esc 会打开开始菜单。";
    }
    if (key == VK_DELETE && (modifiers & (MOD_CONTROL | MOD_ALT)) == (MOD_CONTROL | MOD_ALT)) {
        return L"Ctrl+Alt+Del 由系统保留。";
    }
    if (key == VK_F4 && (modifiers & MOD_CONTROL)) {
        return L"Ctrl+F4 是关闭子窗口的系统快捷键。";
    }
    return {};
}

void UnregisterAllHotkeys() {
    for (int id : kHotkeyIds) {
        UnregisterHotKey(g_messageWindow, id);
    }
}

// 返回注册失败的键位说明，空串表示全部成功
std::wstring RegisterAllHotkeys() {
    UnregisterAllHotkeys();
    std::wstring failed;
    for (int id : kHotkeyIds) {
        HotkeySpec spec;
        const std::wstring text = HotkeyText(Config(), id);
        if (!ParseHotkey(text, spec)) {
            if (!failed.empty()) failed += L"、";
            failed += HotkeyLabel(id) + L"（" + text + L" 无法识别）";
            continue;
        }
        if (!RegisterHotKey(g_messageWindow, id, spec.modifiers, spec.key)) {
            if (!failed.empty()) failed += L"、";
            failed += HotkeyLabel(id) + L"（" + text + L"）";
        }
    }
    return failed;
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

bool IsLaunchAtLoginEnabled() {
    HKEY key = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
            0,
            KEY_QUERY_VALUE,
            &key) != ERROR_SUCCESS) {
        return false;
    }

    DWORD type = 0;
    DWORD size = 0;
    const bool exists =
        RegQueryValueExW(key, L"Mote", nullptr, &type, nullptr, &size) == ERROR_SUCCESS;
    RegCloseKey(key);
    return exists;
}

bool SetLaunchAtLogin(bool enabled) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
            0,
            KEY_SET_VALUE,
            &key) != ERROR_SUCCESS) {
        return false;
    }

    bool ok = false;
    if (enabled) {
        wchar_t path[MAX_PATH]{};
        if (GetModuleFileNameW(nullptr, path, MAX_PATH) > 0) {
            const std::wstring command = L"\"" + std::wstring(path) + L"\"";
            ok = RegSetValueExW(
                key,
                L"Mote",
                0,
                REG_SZ,
                reinterpret_cast<const BYTE*>(command.c_str()),
                static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t))
            ) == ERROR_SUCCESS;
        }
    } else {
        const LONG result = RegDeleteValueW(key, L"Mote");
        ok = result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND;
    }

    RegCloseKey(key);
    return ok;
}

void MigrateLegacyLaunchAtLogin() {
    const wchar_t* legacyName = L"Lingo" L"lite";
    HKEY key = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
            0,
            KEY_QUERY_VALUE | KEY_SET_VALUE,
            &key) != ERROR_SUCCESS) {
        return;
    }

    auto exists = [&](const wchar_t* name) {
        DWORD size = 0;
        return RegQueryValueExW(key, name, nullptr, nullptr, nullptr, &size) == ERROR_SUCCESS;
    };

    const bool current = exists(L"Mote");
    if (exists(legacyName)) {
        if (!current) {
            SetLaunchAtLogin(true);
        }
        RegDeleteValueW(key, legacyName);
    }
    RegCloseKey(key);
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
    const std::wstring tip =
        L"Mote · " + HotkeyText(Config(), kHotkeySelection) + L" 选中翻译";
    wcscpy_s(g_trayIcon.szTip, tip.c_str());
    Shell_NotifyIconW(NIM_ADD, &g_trayIcon);
}

void UpdateTrayTip() {
    if (!g_trayIcon.hWnd) {
        return;
    }
    const std::wstring tip =
        L"Mote · " + HotkeyText(Config(), kHotkeySelection) + L" 选中翻译";
    wcscpy_s(g_trayIcon.szTip, tip.c_str());
    g_trayIcon.uFlags = NIF_TIP;
    Shell_NotifyIconW(NIM_MODIFY, &g_trayIcon);
}

void RemoveTrayIcon() {
    Shell_NotifyIconW(NIM_DELETE, &g_trayIcon);
}

void ShowBalloon(const std::wstring& message) {
    NOTIFYICONDATAW data = g_trayIcon;
    data.uFlags = NIF_INFO;
    data.dwInfoFlags = NIIF_INFO;
    wcscpy_s(data.szInfoTitle, L"Mote");
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
    // 换一段原文后回到开头，避免沿用上一次的滚动位置
    SendMessageW(g_sourceEdit, EM_SETSEL, 0, 0);
    SendMessageW(g_sourceEdit, EM_SCROLLCARET, 0, 0);
    PopulateLanguages(g_languageCombo);
    UpdateStatus();

    const int width = std::clamp(Config().popupWidth, 480, 1200);
    const int height = std::clamp(Config().popupHeight, 380, 900);
    if (Config().popupPositioned) {
        SetWindowPos(
            g_popupWindow, HWND_TOPMOST,
            Config().popupX, Config().popupY, width, height,
            SWP_SHOWWINDOW
        );
    } else {
        CenterWindow(g_popupWindow, width, height, -30);
    }
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
    auto item = [&](int id, const wchar_t* title, const std::wstring& hotkey) {
        const std::wstring text = hotkey.empty()
            ? std::wstring(title)
            : std::wstring(title) + L"\t" + hotkey;
        AppendMenuW(menu, MF_STRING, id, text.c_str());
    };
    item(ID_TRAY_INPUT, L"输入翻译", HotkeyText(Config(), kHotkeyInput));
    item(ID_TRAY_SELECTION, L"选中翻译", HotkeyText(Config(), kHotkeySelection));
    item(ID_TRAY_CLIPBOARD, L"剪贴翻译", HotkeyText(Config(), kHotkeyClipboard));
    item(ID_TRAY_SCREENSHOT, L"截图翻译", HotkeyText(Config(), kHotkeyScreenshot));
    item(ID_TRAY_OCR, L"截图 OCR", HotkeyText(Config(), kHotkeyOcr));
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, ID_TRAY_HISTORY, L"历史记录");
    AppendMenuW(menu, MF_STRING, ID_TRAY_SETTINGS, L"设置");
    AppendMenuW(menu, MF_STRING, ID_TRAY_ABOUT, L"关于 Mote");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, ID_TRAY_EXIT, L"退出 Mote");

    SetForegroundWindow(g_messageWindow);
    TrackPopupMenu(menu, TPM_RIGHTBUTTON, cursor.x, cursor.y, 0, g_messageWindow, nullptr);
    PostMessageW(g_messageWindow, WM_NULL, 0, 0);
    DestroyMenu(menu);
}

// 列表经过筛选，行号不能直接当 History 下标用
int SelectedHistoryIndex() {
    if (!g_historyList) {
        return -1;
    }
    const int row = static_cast<int>(SendMessageW(g_historyList, LB_GETCURSEL, 0, 0));
    if (row < 0 || row >= static_cast<int>(g_historyVisible.size())) {
        return -1;
    }
    return g_historyVisible[row];
}

void CopyHistoryEntry(int index, bool source) {
    if (index < 0 || index >= static_cast<int>(History().size())) {
        return;
    }
    const auto& entry = History()[index];
    if (source) {
        if (entry.source.empty()) {
            return;
        }
        SetClipboardText(entry.source);
        ShowBalloon(L"已复制历史原文");
        return;
    }
    for (const auto& result : entry.results) {
        if (result.ok && !result.text.empty()) {
            SetClipboardText(result.text);
            ShowBalloon(L"已复制历史译文");
            return;
        }
    }
}

void RefreshHistoryWindow() {
    if (!g_historyList) {
        return;
    }
    SendMessageW(g_historyList, LB_RESETCONTENT, 0, 0);
    g_historyVisible.clear();

    const std::wstring filter = Trim(g_historyFilter);
    const auto& history = History();
    for (int index = 0; index < static_cast<int>(history.size()); ++index) {
        const auto& entry = history[index];
        std::wstring first;
        for (const auto& result : entry.results) {
            if (result.ok && !result.text.empty()) {
                first = result.text;
                break;
            }
        }
        std::wstring line = L"[" + entry.time + L"]  " + entry.source + L"  →  " + first;
        if (entry.results.size() > 1) {
            line += L"（另有 " + std::to_wstring(entry.results.size() - 1) + L" 个结果）";
        }
        std::replace(line.begin(), line.end(), L'\r', L' ');
        std::replace(line.begin(), line.end(), L'\n', L' ');
        if (!filter.empty() && line.find(filter) == std::wstring::npos) {
            continue;
        }
        if (line.size() > 140) {
            line = line.substr(0, 140) + L"…";
        }
        g_historyVisible.push_back(index);
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
        g_historyWindow = CreateHistory(g_instance);
        if (!g_historyWindow) {
            return;
        }
    }
    if (g_historySearch) {
        SetWindowTextW(g_historySearch, g_historyFilter.c_str());
    }
    RefreshHistoryWindow();
    CenterWindow(g_historyWindow, 640, 540);
    SetForegroundWindow(g_historyWindow);
}


// 设置页用草稿保存，取消/关窗丢弃；快捷键录制也先写草稿
std::wstring g_draftHotkeys[5];
bool g_draftAutoCopy = false;
int g_draftPopupWidth = 540;
int g_draftPopupHeight = 470;

void AddPageControl(int page, HWND control) {
    if (control) {
        g_pageControls[page].push_back(control);
    }
}

void ShowSettingsPage(int page) {
    if (!g_settingsTab) {
        return;
    }
    for (int index = 0; index < 4; ++index) {
        const int command = index == page ? SW_SHOW : SW_HIDE;
        for (HWND control : g_pageControls[index]) {
            ShowWindow(control, command);
        }
    }
    TabCtrl_SetCurSel(g_settingsTab, page);
}

void RefreshHotkeyButtons() {
    for (int i = 0; i < 5; ++i) {
        if (g_hotkeyButtons[i]) {
            const std::wstring text = (g_recordingHotkey == kHotkeyIds[i])
                ? L"按下新的组合键…"
                : (g_draftHotkeys[i].empty() ? L"未设置" : g_draftHotkeys[i]);
            SetWindowTextW(g_hotkeyButtons[i], text.c_str());
        }
    }
}

void FinishHotkeyRecording() {
    g_recordingHotkey = 0;
    RefreshHotkeyButtons();
    RegisterAllHotkeys();
}

LRESULT CALLBACK HotkeyRecorderProc(
    HWND control,
    UINT message,
    WPARAM wParam,
    LPARAM lParam,
    UINT_PTR,
    DWORD_PTR id
) {
    if (g_recordingHotkey == 0 || (message != WM_KEYDOWN && message != WM_SYSKEYDOWN)) {
        return DefSubclassProc(control, message, wParam, lParam);
    }

    const int hotkeyId = static_cast<int>(id);
    const UINT key = static_cast<UINT>(wParam);
    if (key == VK_ESCAPE) {
        FinishHotkeyRecording();
        return 0;
    }
    // 只按下修饰键时继续等真正的键
    if (key == VK_CONTROL || key == VK_MENU || key == VK_SHIFT
        || key == VK_LWIN || key == VK_RWIN) {
        return 0;
    }
    if (!((key >= L'A' && key <= L'Z') || (key >= L'0' && key <= L'9')
          || (key >= VK_F1 && key <= VK_F12))) {
        MessageBoxW(
            g_settingsWindow,
            L"只支持字母、数字和 F1–F12。",
            L"Mote",
            MB_OK | MB_ICONWARNING
        );
        return 0;
    }

    UINT modifiers = 0;
    if (GetKeyState(VK_CONTROL) & 0x8000) modifiers |= MOD_CONTROL;
    if (GetKeyState(VK_MENU) & 0x8000) modifiers |= MOD_ALT;
    if (GetKeyState(VK_SHIFT) & 0x8000) modifiers |= MOD_SHIFT;
    if ((GetKeyState(VK_LWIN) & 0x8000) || (GetKeyState(VK_RWIN) & 0x8000)) {
        modifiers |= MOD_WIN;
    }

    const std::wstring rejection = HotkeyRejection(modifiers, key);
    if (!rejection.empty()) {
        MessageBoxW(g_settingsWindow, rejection.c_str(), L"Mote", MB_OK | MB_ICONWARNING);
        return 0;
    }

    const std::wstring text = FormatHotkey(modifiers, key);
    for (int i = 0; i < 5; ++i) {
        if (kHotkeyIds[i] != hotkeyId && g_draftHotkeys[i] == text) {
            MessageBoxW(
                g_settingsWindow,
                L"这个组合已经分配给另一个动作了。",
                L"Mote",
                MB_OK | MB_ICONWARNING
            );
            return 0;
        }
    }

    for (int i = 0; i < 5; ++i) {
        if (kHotkeyIds[i] == hotkeyId) {
            g_draftHotkeys[i] = text;
        }
    }
    FinishHotkeyRecording();
    return 0;
}

const wchar_t* kPresetNames[] = {
    L"自定义",
    L"OpenAI",
    L"DeepSeek",
    L"Ollama",
    L"LM Studio",
};

const wchar_t* kPresetEndpoints[] = {
    L"",
    L"https://api.openai.com/v1",
    L"https://api.deepseek.com/v1",
    L"http://localhost:11434/v1",
    L"http://localhost:1234/v1",
};

const wchar_t* kPresetModels[] = {
    L"",
    L"gpt-4o-mini",
    L"deepseek-chat",
    L"qwen2.5:7b",
    L"local-model",
};

void ApplyPreset(HWND combo) {
    const int index = static_cast<int>(SendMessageW(combo, CB_GETCURSEL, 0, 0));
    if (index <= 0 || index >= static_cast<int>(std::size(kPresetEndpoints))) {
        return;
    }
    SetWindowTextW(g_setEndpoint, kPresetEndpoints[index]);
    if (g_setModelCombo) {
        SetWindowTextW(g_setModelCombo, kPresetModels[index]);
    }
}

void FetchModels() {
    AppConfig config = Config();
    ReadSettings(config);
    if (config.endpoint.empty()) {
        MessageBoxW(g_settingsWindow, L"请先填写接口地址。", L"Mote", MB_OK | MB_ICONWARNING);
        return;
    }
    if (g_setFetchModels) {
        EnableWindow(g_setFetchModels, FALSE);
        SetWindowTextW(g_setFetchModels, L"获取中…");
    }
    std::thread([config]() {
        try {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
        } catch (...) {
        }
        std::vector<std::wstring> models;
        std::wstring error;
        const bool ok = ListModels(config, models, error);
        std::wstring message;
        if (ok) {
            message = L"共 " + std::to_wstring(models.size()) + L" 个模型，已填入下拉列表。";
            const size_t limit = std::min<size_t>(models.size(), 50);
            for (size_t i = 0; i < limit; ++i) {
                message += L"\r\n" + models[i];
            }
        } else {
            message = L"获取失败：" + error;
        }
        // 先交回 UI 线程填下拉框（避免跨线程动控件），再弹结果说明
        if (IsWindow(g_settingsWindow)) {
            auto* payload = ok ? new std::vector<std::wstring>(std::move(models)) : nullptr;
            PostMessageW(
                g_settingsWindow,
                WM_APP_MODEL_LIST,
                ok ? 1 : 0,
                reinterpret_cast<LPARAM>(payload)
            );
        }
        MessageBoxW(nullptr, message.c_str(), L"Mote 获取模型", MB_OK | MB_ICONINFORMATION);
        try {
            winrt::uninit_apartment();
        } catch (...) {
        }
    }).detach();
}

void ShowSettingsWindow() {
    if (!g_settingsWindow) {
        g_settingsWindow = CreateSettings(g_instance);
        if (!g_settingsWindow) {
            return;
        }
    }

    const AppConfig config = Config();
    SetWindowTextW(g_setEndpoint, config.endpoint.c_str());
    SetWindowTextW(g_setModel, config.model.c_str());
    SetWindowTextW(g_setKey, config.aiKey.c_str());
    SetWindowTextW(g_setBaiduID, config.baiduAppID.c_str());
    SetWindowTextW(g_setBaiduKey, config.baiduKey.c_str());
    SetWindowTextW(
        g_setPrompt,
        (config.systemPrompt.empty() ? DefaultSystemPrompt() : config.systemPrompt).c_str()
    );
    SendMessageW(
        g_setLLMCheck,
        BM_SETCHECK,
        config.llmEnabled ? BST_CHECKED : BST_UNCHECKED,
        0
    );
    SendMessageW(
        g_setBaiduCheck,
        BM_SETCHECK,
        config.baiduEnabled ? BST_CHECKED : BST_UNCHECKED,
        0
    );
    SendMessageW(
        g_setLaunchCheck,
        BM_SETCHECK,
        IsLaunchAtLoginEnabled() ? BST_CHECKED : BST_UNCHECKED,
        0
    );

    g_draftAutoCopy = config.autoCopy;
    SendMessageW(
        g_setAutoCopyCheck,
        BM_SETCHECK,
        config.autoCopy ? BST_CHECKED : BST_UNCHECKED,
        0
    );
    SetWindowTextW(g_setPopupWidth, std::to_wstring(config.popupWidth).c_str());
    SetWindowTextW(g_setPopupHeight, std::to_wstring(config.popupHeight).c_str());

    for (int i = 0; i < 5; ++i) {
        g_draftHotkeys[i] = HotkeyText(Config(), kHotkeyIds[i]);
    }
    g_recordingHotkey = 0;
    RefreshHotkeyButtons();

    SendMessageW(g_setLanguage, CB_RESETCONTENT, 0, 0);
    for (const auto* language : kLanguages) {
        SendMessageW(g_setLanguage, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(language));
    }
    int index = 0;
    for (int i = 0; i < static_cast<int>(std::size(kLanguages)); ++i) {
        if (config.targetLanguage == kLanguages[i]) {
            index = i;
            break;
        }
    }
    SendMessageW(g_setLanguage, CB_SETCURSEL, index, 0);

    CenterWindow(g_settingsWindow, 680, 620);
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
    config.autoCopy = SendMessageW(g_setAutoCopyCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;

    // 提示词与内置一致时不落盘，方便以后升级内置版本
    const std::wstring prompt = Trim(GetText(g_setPrompt));
    config.systemPrompt = (prompt == Trim(DefaultSystemPrompt())) ? L"" : prompt;

    const int width = _wtoi(Trim(GetText(g_setPopupWidth)).c_str());
    const int height = _wtoi(Trim(GetText(g_setPopupHeight)).c_str());
    config.popupWidth = std::clamp(width, 480, 1200);
    config.popupHeight = std::clamp(height, 380, 900);
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
        MessageBoxW(nullptr, message.c_str(), L"Mote 测试", MB_OK | MB_ICONINFORMATION);
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


// 弹窗按当前客户区重排，窗口可拖动右下角改变尺寸
void LayoutPopup(int width, int height) {
    const int margin = 16;
    const int contentWidth = std::max(200, width - margin * 2);

    const int closeX = width - margin - 24;
    const int settingsX = closeX - 8 - 50;
    const int historyX = settingsX - 6 - 50;
    const int languageX = std::max(margin + 120, historyX - 8 - 110);

    if (g_popupTitle) MoveWindow(g_popupTitle, margin, 12, 120, 24, TRUE);
    if (g_languageCombo) MoveWindow(g_languageCombo, languageX, 10, 110, 200, TRUE);
    if (g_popupHistory) MoveWindow(g_popupHistory, historyX, 10, 50, 26, TRUE);
    if (g_popupSettings) MoveWindow(g_popupSettings, settingsX, 10, 50, 26, TRUE);
    if (g_popupClose) MoveWindow(g_popupClose, closeX, 10, 24, 26, TRUE);

    if (g_popupSourceLabel) MoveWindow(g_popupSourceLabel, margin, 48, 100, 20, TRUE);

    const int sourceTop = 68;
    const int body = std::max(160, height - sourceTop - margin);
    const int sourceHeight = std::max(60, static_cast<int>(body * 0.34));
    const int buttonTop = sourceTop + sourceHeight + 8;
    const int targetLabelTop = buttonTop + 30 + 10;
    const int targetTop = targetLabelTop + 20;
    const int targetHeight = std::max(60, height - targetTop - margin);

    if (g_sourceEdit) MoveWindow(g_sourceEdit, margin, sourceTop, contentWidth, sourceHeight, TRUE);
    if (g_translateButton) MoveWindow(g_translateButton, margin, buttonTop, 90, 30, TRUE);
    if (g_statusLabel) MoveWindow(g_statusLabel, margin + 100, buttonTop + 6, 300, 20, TRUE);
    if (g_popupOutputLabel) MoveWindow(g_popupOutputLabel, margin, targetLabelTop, 100, 20, TRUE);
    if (g_outputEdit) MoveWindow(g_outputEdit, margin, targetTop, contentWidth, targetHeight, TRUE);
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
        g_popupTitle = CreateControl(
            L"STATIC", L"Mote",
            WS_CHILD | WS_VISIBLE,
            16, 12, 160, 24, window, -1
        );
        g_languageCombo = CreateControl(
            WC_COMBOBOXW, L"",
            WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
            300, 10, 110, 200, window, ID_LANGUAGE
        );
        g_popupHistory = CreateControl(
            L"BUTTON", L"历史",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            418, 10, 50, 26, window, ID_HISTORY
        );
        g_popupSettings = CreateControl(
            L"BUTTON", L"设置",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            472, 10, 50, 26, window, ID_SETTINGS
        );
        g_popupClose = CreateControl(
            L"BUTTON", L"×",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            526, 10, 24, 26, window, ID_CLOSE
        );

        g_popupSourceLabel = CreateControl(
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

        g_popupOutputLabel = CreateControl(
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

        RECT client{};
        GetClientRect(window, &client);
        LayoutPopup(client.right, client.bottom);
        return 0;
    }

    case WM_SIZE:
        if (wParam != SIZE_MINIMIZED) {
            LayoutPopup(LOWORD(lParam), HIWORD(lParam));
        }
        return 0;

    case WM_GETMINMAXINFO: {
        auto* info = reinterpret_cast<MINMAXINFO*>(lParam);
        info->ptMinTrackSize.x = 480;
        info->ptMinTrackSize.y = 380;
        return 0;
    }

    case WM_EXITSIZEMOVE: {
        RECT rect{};
        GetWindowRect(window, &rect);
        RECT client{};
        GetClientRect(window, &client);
        Config().popupPositioned = true;
        Config().popupX = rect.left;
        Config().popupY = rect.top;
        Config().popupWidth = client.right;
        Config().popupHeight = client.bottom;
        SaveConfig();
        return 0;
    }

    case WM_ACTIVATE:
        if (LOWORD(wParam) == WA_INACTIVE) {
            if (g_suppressAutoHide) {
                // 点了弹窗里的「设置」「历史」，这次失焦不该收起
                g_suppressAutoHide = false;
            } else {
                HidePopup();
            }
        }
        return 0;

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
            g_suppressAutoHide = true;
            ShowSettingsWindow();
            return 0;
        }
        if (id == ID_HISTORY) {
            g_suppressAutoHide = true;
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
            if (Config().autoCopy) {
                for (const auto& result : payload->results) {
                    if (result.ok && !result.text.empty()) {
                        SetClipboardText(result.text);
                        break;
                    }
                }
            }
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
    windowClass.lpszClassName = L"MotePopup";
    RegisterClassExW(&windowClass);

    return CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        L"MotePopup",
        L"Mote",
        WS_POPUP | WS_THICKFRAME,
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


const wchar_t* kSettingsPageTitles[] = {L"通用", L"服务", L"翻译", L"历史"};

HWND PageControl(
    int page,
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
    HWND control = CreateControl(
        className, text, WS_CHILD | style, x, y, width, height, parent, id, exStyle
    );
    AddPageControl(page, control);
    return control;
}

void CreateGeneralPage(HWND parent) {
    int y = 52;
    g_setLaunchCheck = PageControl(
        0, L"BUTTON", L"开机自动启动", WS_VISIBLE | BS_AUTOCHECKBOX,
        28, y, 240, 24, parent, ID_SET_LAUNCH
    );
    y += 32;
    g_setAutoCopyCheck = PageControl(
        0, L"BUTTON", L"翻译完成后自动复制译文", WS_VISIBLE | BS_AUTOCHECKBOX,
        28, y, 280, 24, parent, ID_SET_AUTOCOPY
    );

    y += 40;
    PageControl(
        0, L"STATIC", L"全局快捷键：点按钮后按下新的组合键，Esc 放弃",
        WS_VISIBLE, 28, y, 520, 20, parent, -1
    );
    y += 26;
    for (int i = 0; i < 5; ++i) {
        PageControl(
            0, L"STATIC", HotkeyLabel(kHotkeyIds[i]),
            WS_VISIBLE, 28, y + 6, 110, 20, parent, -1
        );
        g_hotkeyButtons[i] = PageControl(
            0, L"BUTTON", L"", WS_VISIBLE | BS_PUSHBUTTON,
            150, y, 220, 30, parent, ID_SET_HOTKEY_BASE + i
        );
        SetWindowSubclass(
            g_hotkeyButtons[i],
            HotkeyRecorderProc,
            static_cast<UINT_PTR>(kHotkeyIds[i]),
            static_cast<DWORD_PTR>(kHotkeyIds[i])
        );
        y += 36;
    }

    y += 10;
    PageControl(0, L"STATIC", L"弹窗尺寸", WS_VISIBLE, 28, y, 200, 20, parent, -1);
    y += 26;
    PageControl(0, L"STATIC", L"宽度", WS_VISIBLE, 28, y + 4, 40, 20, parent, -1);
    g_setPopupWidth = PageControl(
        0, L"EDIT", L"", WS_VISIBLE | WS_BORDER | ES_NUMBER,
        72, y, 70, 26, parent, ID_SET_POPUP_WIDTH, WS_EX_CLIENTEDGE
    );
    PageControl(0, L"STATIC", L"高度", WS_VISIBLE, 160, y + 4, 40, 20, parent, -1);
    g_setPopupHeight = PageControl(
        0, L"EDIT", L"", WS_VISIBLE | WS_BORDER | ES_NUMBER,
        204, y, 70, 26, parent, ID_SET_POPUP_HEIGHT, WS_EX_CLIENTEDGE
    );
    PageControl(
        0, L"STATIC", L"像素；也可以在弹窗右下角拖动调整，位置会自动记住。",
        WS_VISIBLE, 286, y + 4, 340, 20, parent, -1
    );
}

void CreateServicePage(HWND parent) {
    int y = 52;
    g_setLLMCheck = PageControl(
        1, L"BUTTON", L"启用 AI 翻译", WS_VISIBLE | BS_AUTOCHECKBOX,
        28, y, 200, 24, parent, ID_SET_LLM
    );

    y += 34;
    PageControl(1, L"STATIC", L"服务预设", WS_VISIBLE, 28, y + 4, 70, 20, parent, -1);
    g_setPreset = PageControl(
        1, WC_COMBOBOXW, L"", WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
        110, y, 200, 200, parent, ID_SET_PRESET
    );
    for (const auto* name : kPresetNames) {
        SendMessageW(g_setPreset, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(name));
    }
    SendMessageW(g_setPreset, CB_SETCURSEL, 0, 0);

    y += 36;
    PageControl(1, L"STATIC", L"接口地址", WS_VISIBLE, 28, y + 4, 70, 20, parent, -1);
    g_setEndpoint = PageControl(
        1, L"EDIT", L"", WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
        110, y, 500, 26, parent, ID_SET_ENDPOINT, WS_EX_CLIENTEDGE
    );

    y += 36;
    PageControl(1, L"STATIC", L"模型", WS_VISIBLE, 28, y + 4, 70, 20, parent, -1);
    g_setModel = g_setModelCombo = PageControl(
        1, WC_COMBOBOXW, L"", WS_VISIBLE | CBS_DROPDOWN | WS_VSCROLL,
        110, y, 360, 240, parent, ID_SET_MODEL
    );
    g_setFetchModels = PageControl(
        1, L"BUTTON", L"获取模型", WS_VISIBLE | BS_PUSHBUTTON,
        480, y - 2, 130, 28, parent, ID_SET_FETCH_MODELS
    );

    y += 36;
    PageControl(1, L"STATIC", L"API Key", WS_VISIBLE, 28, y + 4, 70, 20, parent, -1);
    g_setKey = PageControl(
        1, L"EDIT", L"", WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL | ES_PASSWORD,
        110, y, 500, 26, parent, ID_SET_KEY, WS_EX_CLIENTEDGE
    );

    y += 44;
    g_setBaiduCheck = PageControl(
        1, L"BUTTON", L"启用百度翻译", WS_VISIBLE | BS_AUTOCHECKBOX,
        28, y, 200, 24, parent, ID_SET_BAIDU
    );

    y += 34;
    PageControl(1, L"STATIC", L"AppID", WS_VISIBLE, 28, y + 4, 70, 20, parent, -1);
    g_setBaiduID = PageControl(
        1, L"EDIT", L"", WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
        110, y, 500, 26, parent, ID_SET_BAIDU_ID, WS_EX_CLIENTEDGE
    );

    y += 36;
    PageControl(1, L"STATIC", L"密钥", WS_VISIBLE, 28, y + 4, 70, 20, parent, -1);
    g_setBaiduKey = PageControl(
        1, L"EDIT", L"", WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL | ES_PASSWORD,
        110, y, 500, 26, parent, ID_SET_BAIDU_KEY, WS_EX_CLIENTEDGE
    );

    y += 44;
    PageControl(
        1, L"BUTTON", L"测试 AI", WS_VISIBLE | BS_PUSHBUTTON,
        28, y, 110, 30, parent, ID_SET_TEST_AI
    );
    PageControl(
        1, L"BUTTON", L"测试百度", WS_VISIBLE | BS_PUSHBUTTON,
        146, y, 110, 30, parent, ID_SET_TEST_BAIDU
    );
    PageControl(
        1, L"STATIC", L"密钥保存在 Windows 凭据管理器",
        WS_VISIBLE, 286, y + 6, 320, 20, parent, -1
    );
}

void CreateTranslatePage(HWND parent) {
    int y = 52;
    PageControl(2, L"STATIC", L"目标语言", WS_VISIBLE, 28, y + 4, 70, 20, parent, -1);
    g_setLanguage = PageControl(
        2, WC_COMBOBOXW, L"", WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
        110, y, 220, 200, parent, ID_SET_LANGUAGE
    );

    y += 44;
    PageControl(
        2, L"STATIC", L"系统提示词（发给模型的开头说明，可用 {targetLang} 引用目标语言）",
        WS_VISIBLE, 28, y, 560, 20, parent, -1
    );
    y += 26;
    g_setPrompt = PageControl(
        2, L"EDIT", L"",
        WS_VISIBLE | WS_BORDER | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_VSCROLL,
        28, y, 580, 320, parent, ID_SET_PROMPT, WS_EX_CLIENTEDGE
    );

    y += 332;
    PageControl(
        2, L"BUTTON", L"恢复默认", WS_VISIBLE | BS_PUSHBUTTON,
        28, y, 110, 30, parent, ID_SET_PROMPT_RESET
    );
    PageControl(
        2, L"STATIC", L"留空则使用内置提示词。",
        WS_VISIBLE, 150, y + 6, 300, 20, parent, -1
    );
}

void CreateHistoryPage(HWND parent) {
    PageControl(
        3, L"STATIC",
        L"翻译历史保存在 %APPDATA%\\Mote\\history.json，最多保留 100 条。",
        WS_VISIBLE, 28, 52, 560, 20, parent, -1
    );
    PageControl(
        3, L"BUTTON", L"打开历史窗口", WS_VISIBLE | BS_PUSHBUTTON,
        28, 84, 140, 30, parent, ID_SET_OPEN_HISTORY
    );
    PageControl(
        3, L"BUTTON", L"清空历史", WS_VISIBLE | BS_PUSHBUTTON,
        180, 84, 110, 30, parent, ID_SET_CLEAR_HISTORY
    );
}

LRESULT CALLBACK SettingsWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_CREATE: {
        g_settingsTab = CreateControl(
            WC_TABCONTROLW, L"",
            WS_CHILD | WS_VISIBLE,
            10, 10, 636, 566, window, ID_SET_TAB
        );
        for (int i = 0; i < 4; ++i) {
            TCITEMW tab{};
            tab.mask = TCIF_TEXT;
            tab.pszText = const_cast<LPWSTR>(kSettingsPageTitles[i]);
            TabCtrl_InsertItem(g_settingsTab, i, &tab);
        }

        CreateGeneralPage(window);
        CreateServicePage(window);
        CreateTranslatePage(window);
        CreateHistoryPage(window);

        ApplyFont(window, g_font);
        ShowSettingsPage(0);
        return 0;
    }

    case WM_NOTIFY: {
        const auto* header = reinterpret_cast<NMHDR*>(lParam);
        if (header && header->hwndFrom == g_settingsTab && header->code == TCN_SELCHANGE) {
            ShowSettingsPage(TabCtrl_GetCurSel(g_settingsTab));
            return 0;
        }
        break;
    }

    case WM_APP_MODEL_LIST: {
        if (g_setFetchModels) {
            EnableWindow(g_setFetchModels, TRUE);
            SetWindowTextW(g_setFetchModels, L"获取模型");
        }
        auto* models = reinterpret_cast<std::vector<std::wstring>*>(lParam);
        if (models && g_setModel) {
            const std::wstring current = Trim(GetText(g_setModel));
            SendMessageW(g_setModel, CB_RESETCONTENT, 0, 0);
            for (const auto& model : *models) {
                SendMessageW(g_setModel, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(model.c_str()));
            }
            SetWindowTextW(g_setModel, current.empty() ? L"" : current.c_str());
        }
        delete models;
        return 0;
    }

    case WM_COMMAND: {
        const int id = LOWORD(wParam);
        const int notification = HIWORD(wParam);

        if (id == ID_SET_SAVE) {
            AppConfig config = Config();
            ReadSettings(config);
            for (int i = 0; i < 5; ++i) {
                HotkeyText(config, kHotkeyIds[i]) = g_draftHotkeys[i];
            }
            Config() = config;
            SaveConfig();
            if (!SetLaunchAtLogin(
                    SendMessageW(g_setLaunchCheck, BM_GETCHECK, 0, 0) == BST_CHECKED)) {
                MessageBoxW(
                    window,
                    L"无法写入开机自启动项，请检查注册表权限。",
                    L"Mote",
                    MB_OK | MB_ICONWARNING
                );
            }
            // 热键改了要重新注册，占用冲突在这里一次性告诉用户
            const std::wstring failed = RegisterAllHotkeys();
            if (!failed.empty()) {
                const std::wstring message = failed + L" 注册失败，可能被其他程序占用。";
                MessageBoxW(window, message.c_str(), L"Mote", MB_OK | MB_ICONWARNING);
            }
            UpdateTrayTip();
            PopulateLanguages(g_languageCombo);
            ShowWindow(window, SW_HIDE);
            return 0;
        }
        if (id == ID_SET_CANCEL) {
            FinishHotkeyRecording();
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
        if (id == ID_SET_PRESET && notification == CBN_SELCHANGE) {
            ApplyPreset(g_setPreset);
            return 0;
        }
        if (id == ID_SET_FETCH_MODELS) {
            FetchModels();
            return 0;
        }
        if (id == ID_SET_PROMPT_RESET) {
            SetWindowTextW(g_setPrompt, DefaultSystemPrompt().c_str());
            return 0;
        }
        if (id == ID_SET_AUTOCOPY) {
            g_draftAutoCopy = SendMessageW(g_setAutoCopyCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
            return 0;
        }
        if (id >= ID_SET_HOTKEY_BASE && id < ID_SET_HOTKEY_BASE + 5) {
            const int index = id - ID_SET_HOTKEY_BASE;
            // 录制期间先放开自己的热键，否则按到已注册的组合会直接触发动作
            UnregisterAllHotkeys();
            g_recordingHotkey = kHotkeyIds[index];
            RefreshHotkeyButtons();
            SetFocus(g_hotkeyButtons[index]);
            return 0;
        }
        if (id == ID_SET_OPEN_HISTORY) {
            ShowHistoryWindow();
            return 0;
        }
        if (id == ID_SET_CLEAR_HISTORY) {
            if (MessageBoxW(
                    window,
                    L"确定清空全部翻译历史？此操作无法撤销。",
                    L"Mote",
                    MB_YESNO | MB_ICONWARNING
                ) == IDYES) {
                History().clear();
                SaveHistory();
                RefreshHistoryWindow();
            }
            return 0;
        }
        break;
    }

    case WM_CLOSE:
        FinishHotkeyRecording();
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
    windowClass.lpszClassName = L"MoteSettings";
    RegisterClassExW(&windowClass);

    return CreateWindowExW(
        WS_EX_DLGMODALFRAME | WS_EX_TOOLWINDOW,
        L"MoteSettings",
        L"Mote 设置",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        680,
        620,
        nullptr,
        nullptr,
        instance,
        nullptr
    );
}

LRESULT CALLBACK HistoryWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_CREATE:
        g_historySearch = CreateControl(
            L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
            12, 14, 400, 26, window, ID_HISTORY_SEARCH, WS_EX_CLIENTEDGE
        );
        SendMessageW(
            g_historySearch,
            EM_SETCUEBANNER,
            TRUE,
            reinterpret_cast<LPARAM>(L"搜索原文或译文")
        );
        g_historyList = CreateControl(
            L"LISTBOX", L"",
            WS_CHILD | WS_VISIBLE | WS_BORDER | WS_VSCROLL | LBS_NOTIFY,
            12, 52, 596, 392, window, ID_HISTORY_LIST
        );
        CreateControl(
            L"BUTTON", L"复制译文",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            12, 456, 100, 30, window, ID_HISTORY_COPY
        );
        CreateControl(
            L"BUTTON", L"复制原文",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            120, 456, 100, 30, window, ID_HISTORY_COPY_SOURCE
        );
        CreateControl(
            L"BUTTON", L"清空",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            228, 456, 90, 30, window, ID_HISTORY_CLEAR
        );
        CreateControl(
            L"BUTTON", L"关闭",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            528, 456, 80, 30, window, ID_HISTORY_CLOSE
        );
        ApplyFont(window, g_font);
        return 0;

    case WM_COMMAND: {
        const int id = LOWORD(wParam);
        if (id == ID_HISTORY_SEARCH && HIWORD(wParam) == EN_CHANGE) {
            g_historyFilter = GetText(g_historySearch);
            RefreshHistoryWindow();
            return 0;
        }
        if (id == ID_HISTORY_LIST && HIWORD(wParam) == LBN_DBLCLK) {
            CopyHistoryEntry(SelectedHistoryIndex(), false);
            return 0;
        }
        if (id == ID_HISTORY_COPY) {
            CopyHistoryEntry(SelectedHistoryIndex(), false);
            return 0;
        }
        if (id == ID_HISTORY_COPY_SOURCE) {
            CopyHistoryEntry(SelectedHistoryIndex(), true);
            return 0;
        }
        if (id == ID_HISTORY_CLEAR) {
            if (MessageBoxW(
                    window,
                    L"清空全部历史记录？此操作不可撤销。",
                    L"Mote",
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

    case WM_CONTEXTMENU: {
        POINT cursor{};
        GetCursorPos(&cursor);
        HMENU menu = CreatePopupMenu();
        AppendMenuW(menu, MF_STRING, ID_HISTORY_COPY, L"复制译文");
        AppendMenuW(menu, MF_STRING, ID_HISTORY_COPY_SOURCE, L"复制原文");
        SetForegroundWindow(window);
        const int command = TrackPopupMenu(
            menu,
            TPM_RETURNCMD | TPM_RIGHTBUTTON,
            cursor.x, cursor.y, 0, window, nullptr
        );
        DestroyMenu(menu);
        if (command == ID_HISTORY_COPY) {
            CopyHistoryEntry(SelectedHistoryIndex(), false);
            return 0;
        }
        if (command == ID_HISTORY_COPY_SOURCE) {
            CopyHistoryEntry(SelectedHistoryIndex(), true);
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
    windowClass.lpszClassName = L"MoteHistory";
    RegisterClassExW(&windowClass);

    return CreateWindowExW(
        WS_EX_DLGMODALFRAME | WS_EX_TOOLWINDOW,
        L"MoteHistory",
        L"Mote 历史记录",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        660,
        540,
        nullptr,
        nullptr,
        instance,
        nullptr
    );
}

void HandleSelection() {
    const std::wstring text = Trim(ReadSelectedText());
    if (text.empty()) {
        // 与 mac 端一致：没读到内容就不弹空窗口
        ShowBalloon(L"没有获取到选中文本");
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
        case ID_TRAY_ABOUT: {
            const std::wstring message =
                L"Mote\r\n\r\n轻量、原生的 AI 翻译工具。\r\n"
                L"翻译在本地发起，不经过 Mote 服务器；不收集遥测。\r\n\r\n"
                L"github.com/demoutgg/Mote";
            MessageBoxW(g_messageWindow, message.c_str(), L"关于 Mote", MB_OK | MB_ICONINFORMATION);
            break;
        }
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
    windowClass.lpszClassName = L"MoteMessage";
    RegisterClassExW(&windowClass);

    return CreateWindowExW(
        0,
        L"MoteMessage",
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

    // 设置页用 Tab 控件分页，必须先初始化 comctl32
    INITCOMMONCONTROLSEX comctl{sizeof(comctl), ICC_TAB_CLASSES | ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&comctl);

    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
    } catch (...) {
    }

    HANDLE mutex = CreateMutexW(nullptr, TRUE, L"MoteSingleInstance");
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
    MigrateLegacyLaunchAtLogin();

    g_messageWindow = CreateMessageWindow(instance);
    g_popupWindow = CreatePopup(instance);
    if (!g_messageWindow || !g_popupWindow) {
        return 1;
    }

    AddTrayIcon();

    const std::wstring failed = RegisterAllHotkeys();
    if (!failed.empty()) {
        const std::wstring message =
            failed + L" 注册失败（被其他程序占用或写法不支持）。可在 设置 → 通用 里换一个组合。";
        MessageBoxW(nullptr, message.c_str(), L"Mote", MB_OK | MB_ICONWARNING);
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
