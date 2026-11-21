#include "app.h"

#include <UIAutomation.h>
#include <UIAutomationClient.h>
#include <wrl/client.h>
#include <oleauto.h>

#include <algorithm>

namespace {

std::wstring Trim(std::wstring value) {
    const auto isSpace = [](wchar_t ch) {
        return ch == L' ' || ch == L'\t' || ch == L'\r' || ch == L'\n';
    };
    while (!value.empty() && isSpace(value.front())) {
        value.erase(value.begin());
    }
    while (!value.empty() && isSpace(value.back())) {
        value.pop_back();
    }
    return value;
}

std::wstring ReadUiaSelection() {
    using Microsoft::WRL::ComPtr;

    ComPtr<IUIAutomation> automation;
    if (FAILED(CoCreateInstance(
            __uuidof(CUIAutomation),
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&automation)))) {
        return {};
    }

    ComPtr<IUIAutomationElement> focused;
    if (FAILED(automation->GetFocusedElement(&focused)) || !focused) {
        return {};
    }

    ComPtr<IUnknown> pattern;
    if (FAILED(focused->GetCurrentPattern(UIA_TextPatternId, &pattern)) || !pattern) {
        return {};
    }

    ComPtr<IUIAutomationTextPattern> textPattern;
    if (FAILED(pattern.As(&textPattern)) || !textPattern) {
        return {};
    }

    ComPtr<IUIAutomationTextRangeArray> ranges;
    if (FAILED(textPattern->GetSelection(&ranges)) || !ranges) {
        return {};
    }

    int count = 0;
    if (FAILED(ranges->get_Length(&count)) || count <= 0) {
        return {};
    }

    std::wstring result;
    for (int index = 0; index < count; ++index) {
        ComPtr<IUIAutomationTextRange> range;
        if (FAILED(ranges->GetElement(index, &range)) || !range) {
            continue;
        }
        BSTR text = nullptr;
        if (SUCCEEDED(range->GetText(-1, &text)) && text) {
            result += text;
            SysFreeString(text);
        }
    }
    return result;
}

void SendCtrlC() {
    INPUT inputs[4]{};
    inputs[0].type = INPUT_KEYBOARD;
    inputs[0].ki.wVk = VK_CONTROL;
    inputs[1].type = INPUT_KEYBOARD;
    inputs[1].ki.wVk = 'C';
    inputs[2].type = INPUT_KEYBOARD;
    inputs[2].ki.wVk = 'C';
    inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
    inputs[3].type = INPUT_KEYBOARD;
    inputs[3].ki.wVk = VK_CONTROL;
    inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(4, inputs, sizeof(INPUT));
}

}  // namespace

std::wstring GetClipboardText() {
    std::wstring result;
    for (int attempt = 0; attempt < 10; ++attempt) {
        if (!OpenClipboard(nullptr)) {
            Sleep(20);
            continue;
        }
        HANDLE data = GetClipboardData(CF_UNICODETEXT);
        if (data) {
            const auto* text = static_cast<const wchar_t*>(GlobalLock(data));
            if (text) {
                result = text;
                GlobalUnlock(data);
            }
        }
        CloseClipboard();
        break;
    }
    return result;
}

void SetClipboardText(const std::wstring& text) {
    if (!OpenClipboard(nullptr)) {
        return;
    }
    EmptyClipboard();

    const size_t bytes = (text.size() + 1) * sizeof(wchar_t);
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (memory) {
        void* target = GlobalLock(memory);
        if (target) {
            memcpy(target, text.c_str(), bytes);
            GlobalUnlock(memory);
            SetClipboardData(CF_UNICODETEXT, memory);
        } else {
            GlobalFree(memory);
        }
    }
    CloseClipboard();
}

std::wstring ReadSelectedText() {
    std::wstring text = Trim(ReadUiaSelection());
    if (!text.empty()) {
        return text;
    }

    const std::wstring previous = GetClipboardText();
    const DWORD sequence = GetClipboardSequenceNumber();

    SendCtrlC();
    for (int attempt = 0; attempt < 25; ++attempt) {
        Sleep(20);
        if (GetClipboardSequenceNumber() != sequence) {
            text = Trim(GetClipboardText());
            break;
        }
    }

    SetClipboardText(previous);
    return text;
}
