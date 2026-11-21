#pragma once

#include <windows.h>
#include <objbase.h>

#include <string>
#include <vector>

constexpr wchar_t kAppName[] = L"Lingolite";
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
    double temperature = 0.2;
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

std::wstring ReadSelectedText();
std::wstring GetClipboardText();
void SetClipboardText(const std::wstring& text);

void StartScreenshotSelection(HWND owner, bool translate);

void RefreshHistoryList();
std::wstring ResolveTargetLanguage(const std::wstring& text);

extern HINSTANCE g_instance;
extern HWND g_messageWindow;
extern HWND g_popupWindow;
