#pragma once

#include <windows.h>
#include <objbase.h>

#include <string>
#include <vector>

constexpr wchar_t kAppName[] = L"Mote";
constexpr UINT WM_APP_TRANSLATE_DONE = WM_APP + 10;
constexpr UINT WM_APP_OCR_DONE = WM_APP + 11;

struct AppConfig {
    std::wstring endpoint = L"https://api.openai.com/v1";
    std::wstring model = L"gpt-4o-mini";
    std::wstring targetLanguage = L"简体中文";
    std::wstring systemPrompt;
    std::wstring baiduAppID;
    std::wstring aiKey;
    std::wstring baiduKey;
    bool llmEnabled = true;
    bool baiduEnabled = false;
    bool autoCopy = false;
    double temperature = 0.2;

    // 弹窗尺寸与位置：positioned 为真时才用 x/y，否则每次居中
    bool popupPositioned = false;
    int popupX = 0;
    int popupY = 0;
    int popupWidth = 540;
    int popupHeight = 470;

    // 快捷键按 "Ctrl+Alt+K" 这类文本存储，注册时再解析
    std::wstring hotkeyInput = L"Alt+A";
    std::wstring hotkeySelection = L"Alt+D";
    std::wstring hotkeyClipboard = L"Alt+V";
    std::wstring hotkeyScreenshot = L"Alt+S";
    std::wstring hotkeyOcr = L"Shift+Alt+S";
};

struct ServiceResult {
    std::wstring title;
    std::wstring text;
    bool ok = true;
};

struct HistoryEntry {
    std::wstring time;
    std::wstring source;
    std::wstring target;
    std::vector<ServiceResult> results;
};

struct OcrPayload {
    std::wstring text;
    bool translate = false;
};

struct TranslationPayload {
    int generation = 0;
    std::wstring source;
    std::wstring target;
    std::vector<ServiceResult> results;
};

AppConfig& Config();
std::vector<HistoryEntry>& History();

void LoadConfig();
void SaveConfig();
void LoadHistory();
void SaveHistory();
void AddHistory(const std::wstring& source,
                const std::wstring& target,
                const std::vector<ServiceResult>& results);

bool TranslateAI(const AppConfig& config,
                 const std::wstring& text,
                 std::wstring& output,
                 std::wstring& error);
bool TranslateBaidu(const AppConfig& config,
                    const std::wstring& text,
                    std::wstring& output,
                    std::wstring& error);

/// 拉取 OpenAI 兼容服务的模型列表，供设置页「获取模型」使用。
bool ListModels(const AppConfig& config,
                std::vector<std::wstring>& models,
                std::wstring& error);

/// 内置的系统提示词，设置页「恢复默认」用。
std::wstring DefaultSystemPrompt();

std::wstring ReadSelectedText();
std::wstring GetClipboardText();
void SetClipboardText(const std::wstring& text);

void StartScreenshotSelection(HWND owner, bool translate);

void RefreshHistoryList();
std::wstring ResolveTargetLanguage(const std::wstring& text);

extern HINSTANCE g_instance;
extern HWND g_messageWindow;
extern HWND g_popupWindow;
