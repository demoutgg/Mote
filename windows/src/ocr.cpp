#include "app.h"

#include <windowsx.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>

#include <thread>
#include <algorithm>
#include <cstring>
#include <cwchar>
#include <cstdio>

namespace {

constexpr COLORREF kKeyColor = RGB(1, 2, 3);
const wchar_t kOverlayClass[] = L"LingoliteOverlay";

HWND g_overlay = nullptr;
POINT g_start{};
POINT g_current{};
bool g_selecting = false;
int g_virtualX = 0;
int g_virtualY = 0;

struct Apartment {
    bool initialized = false;

    Apartment() {
        try {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
            initialized = true;
        } catch (...) {
        }
    }

    ~Apartment() {
        if (initialized) {
            winrt::uninit_apartment();
        }
    }
};

void PaintOverlay(HWND window) {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window, &paint);

    RECT client{};
    GetClientRect(window, &client);
    HBRUSH keyBrush = CreateSolidBrush(kKeyColor);
    FillRect(dc, &client, keyBrush);
    DeleteObject(keyBrush);

    if (g_selecting) {
        const int left = std::min(g_start.x, g_current.x);
        const int top = std::min(g_start.y, g_current.y);
        const int right = std::max(g_start.x, g_current.x);
        const int bottom = std::max(g_start.y, g_current.y);
        const int width = right - left;
        const int height = bottom - top;

        if (width > 1 && height > 1) {
            HPEN blue = CreatePen(PS_SOLID, 2, RGB(80, 155, 255));
            HGDIOBJ oldPen = SelectObject(dc, blue);
            HGDIOBJ oldBrush = SelectObject(dc, GetStockObject(NULL_BRUSH));
            Rectangle(dc, left, top, right, bottom);
            SelectObject(dc, oldBrush);
            SelectObject(dc, oldPen);
            DeleteObject(blue);

            wchar_t sizeText[64]{};
            swprintf_s(sizeText, L"%d × %d", width, height);
            RECT label{left + 6, top + 6, left + 150, top + 32};
            SetBkMode(dc, OPAQUE);
            SetBkColor(dc, RGB(20, 28, 52));
            SetTextColor(dc, RGB(255, 255, 255));
            DrawTextW(dc, sizeText, -1, &label, DT_LEFT | DT_SINGLELINE | DT_VCENTER);
        }
    }

    const wchar_t* hint = L"拖动框选要翻译的区域 · Esc 取消";
    RECT hintRect{
        client.right / 2 - 160,
        40,
        client.right / 2 + 160,
        76
    };
    SetBkMode(dc, OPAQUE);
    SetBkColor(dc, RGB(20, 28, 52));
    SetTextColor(dc, RGB(255, 255, 255));
    DrawTextW(dc, hint, -1, &hintRect, DT_CENTER | DT_SINGLELINE | DT_VCENTER);

    EndPaint(window, &paint);
}

void CaptureAndRecognize(RECT rect, bool translate) {
    Apartment apartment;
    Sleep(120);

    const int width = rect.right - rect.left;
    const int height = rect.bottom - rect.top;
    std::wstring text;

    if (width > 0 && height > 0) {
        HDC screen = GetDC(nullptr);
        HDC memory = CreateCompatibleDC(screen);

        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(info.bmiHeader);
        info.bmiHeader.biWidth = width;
        info.bmiHeader.biHeight = -height;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;

        void* bits = nullptr;
        HBITMAP bitmap = CreateDIBSection(
            screen,
            &info,
            DIB_RGB_COLORS,
            &bits,
            nullptr,
            0
        );

        if (bitmap && bits) {
            HGDIOBJ old = SelectObject(memory, bitmap);
            BitBlt(memory, 0, 0, width, height, screen, rect.left, rect.top, SRCCOPY);

            try {
                using namespace winrt::Windows::Graphics::Imaging;
                using namespace winrt::Windows::Media::Ocr;
                using namespace winrt::Windows::Storage::Streams;

                const uint32_t byteCount = static_cast<uint32_t>(width * height * 4);
                Buffer buffer(byteCount);
                buffer.Length(byteCount);
                memcpy(buffer.data(), bits, byteCount);

                const auto software = SoftwareBitmap::CreateCopyFromBuffer(
                    buffer,
                    BitmapPixelFormat::Bgra8,
                    width,
                    height,
                    BitmapAlphaMode::Ignore
                );

                auto engine = OcrEngine::TryCreateFromUserProfileLanguages();
                if (!engine) {
                    engine = OcrEngine::TryCreateFromLanguage(
                        winrt::Windows::Globalization::Language(L"zh-Hans")
                    );
                }
                if (engine) {
                    const auto result = engine.RecognizeAsync(software).get();
                    for (const auto& line : result.Lines()) {
                        if (!text.empty()) {
                            text += L"\n";
                        }
                        text += line.Text().c_str();
                    }
                }
            } catch (...) {
            }

            SelectObject(memory, old);
        }

        if (bitmap) {
            DeleteObject(bitmap);
        }
        DeleteDC(memory);
        ReleaseDC(nullptr, screen);
    }

    auto* payload = new OcrPayload{text, translate};
    if (g_messageWindow) {
        PostMessageW(g_messageWindow, WM_APP_OCR_DONE, 0, reinterpret_cast<LPARAM>(payload));
    } else {
        delete payload;
    }
}

LRESULT CALLBACK OverlayProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_ERASEBKGND:
        return 1;

    case WM_PAINT:
        PaintOverlay(window);
        return 0;

    case WM_SETCURSOR:
        SetCursor(LoadCursorW(nullptr, IDC_CROSS));
        return TRUE;

    case WM_LBUTTONDOWN: {
        g_selecting = true;
        g_start.x = GET_X_LPARAM(lParam);
        g_start.y = GET_Y_LPARAM(lParam);
        g_current = g_start;
        SetCapture(window);
        InvalidateRect(window, nullptr, TRUE);
        return 0;
    }

    case WM_MOUSEMOVE:
        if (g_selecting) {
            g_current.x = GET_X_LPARAM(lParam);
            g_current.y = GET_Y_LPARAM(lParam);
            InvalidateRect(window, nullptr, TRUE);
        }
        return 0;

    case WM_LBUTTONUP: {
        if (!g_selecting) {
            return 0;
        }
        g_selecting = false;
        g_current.x = GET_X_LPARAM(lParam);
        g_current.y = GET_Y_LPARAM(lParam);
        ReleaseCapture();

        const int left = std::min(g_start.x, g_current.x) + g_virtualX;
        const int top = std::min(g_start.y, g_current.y) + g_virtualY;
        const int right = std::max(g_start.x, g_current.x) + g_virtualX;
        const int bottom = std::max(g_start.y, g_current.y) + g_virtualY;
        const bool translate = GetPropW(window, L"translate") != nullptr;

        DestroyWindow(window);

        RECT rect{left, top, right, bottom};
        if (rect.right - rect.left >= 8 && rect.bottom - rect.top >= 8) {
            std::thread([rect, translate]() {
                CaptureAndRecognize(rect, translate);
            }).detach();
        }
        return 0;
    }

    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) {
            DestroyWindow(window);
            return 0;
        }
        break;

    case WM_DESTROY:
        if (GetCapture() == window) {
            ReleaseCapture();
        }
        g_overlay = nullptr;
        return 0;

    default:
        break;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

}  // namespace

void StartScreenshotSelection(HWND owner, bool translate) {
    if (g_popupWindow) {
        ShowWindow(g_popupWindow, SW_HIDE);
    }

    static bool registered = false;
    if (!registered) {
        WNDCLASSEXW windowClass{};
        windowClass.cbSize = sizeof(windowClass);
        windowClass.lpfnWndProc = OverlayProc;
        windowClass.hInstance = g_instance;
        windowClass.hCursor = LoadCursorW(nullptr, IDC_CROSS);
        windowClass.hbrBackground = CreateSolidBrush(kKeyColor);
        windowClass.lpszClassName = kOverlayClass;
        RegisterClassExW(&windowClass);
        registered = true;
    }

    if (g_overlay) {
        DestroyWindow(g_overlay);
        g_overlay = nullptr;
    }

    g_virtualX = GetSystemMetrics(SM_XVIRTUALSCREEN);
    g_virtualY = GetSystemMetrics(SM_YVIRTUALSCREEN);
    const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);

    g_overlay = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
        kOverlayClass,
        L"",
        WS_POPUP,
        g_virtualX,
        g_virtualY,
        width,
        height,
        nullptr,
        nullptr,
        g_instance,
        nullptr
    );
    if (!g_overlay) {
        return;
    }

    SetPropW(
        g_overlay,
        L"translate",
        translate ? reinterpret_cast<HANDLE>(1) : nullptr
    );
    SetLayeredWindowAttributes(g_overlay, kKeyColor, 0, LWA_COLORKEY);
    ShowWindow(g_overlay, SW_SHOW);
    SetForegroundWindow(g_overlay);
    SetFocus(g_overlay);
}
