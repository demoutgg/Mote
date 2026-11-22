#include "app.h"

#include <winhttp.h>
#include <bcrypt.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>

#include <algorithm>
#include <string>
#include <vector>

namespace {

struct HttpResult {
    int status = 0;
    std::string body;
};

std::wstring Utf8ToWide(const std::string& value) {
    if (value.empty()) {
        return {};
    }
    const int length = MultiByteToWideChar(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0
    );
    std::wstring result(static_cast<size_t>(length), L'\0');
    MultiByteToWideChar(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        result.data(),
        length
    );
    return result;
}

std::string WideToUtf8(const std::wstring& value) {
    if (value.empty()) {
        return {};
    }
    const int length = WideCharToMultiByte(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr
    );
    std::string result(static_cast<size_t>(length), '\0');
    WideCharToMultiByte(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        result.data(),
        length,
        nullptr,
        nullptr
    );
    return result;
}

std::wstring Trim(std::wstring value) {
    while (!value.empty() && (value.back() == L'\r' || value.back() == L'\n' || value.back() == L' ')) {
        value.pop_back();
    }
    size_t start = 0;
    while (start < value.size() && (value[start] == L'\r' || value[start] == L'\n' || value[start] == L' ')) {
        ++start;
    }
    return value.substr(start);
}

std::wstring Truncate(const std::string& value, size_t maxLength = 500) {
    std::wstring text = Trim(Utf8ToWide(value));
    if (text.size() > maxLength) {
        text = text.substr(0, maxLength) + L"…";
    }
    return text;
}

std::wstring NormalizeEndpoint(const std::wstring& raw) {
    std::wstring value = raw;
    while (!value.empty() && value.back() == L'/') {
        value.pop_back();
    }
    if (value.size() >= 17 && value.substr(value.size() - 17) == L"/chat/completions") {
        return value;
    }
    if (value.size() >= 3 && value.substr(value.size() - 3) == L"/v1") {
        return value + L"/chat/completions";
    }
    return value + L"/v1/chat/completions";
}

bool ContainsCjk(const std::wstring& text) {
    for (wchar_t ch : text) {
        const auto code = static_cast<unsigned int>(ch);
        if ((code >= 0x4E00 && code <= 0x9FFF)
            || (code >= 0x3400 && code <= 0x4DBF)
            || (code >= 0x3040 && code <= 0x30FF)
            || (code >= 0xAC00 && code <= 0xD7AF)) {
            return true;
        }
    }
    return false;
}

std::wstring TargetFor(const AppConfig& config, const std::wstring& text) {
    if (config.targetLanguage.rfind(L"自动", 0) != 0) {
        return config.targetLanguage;
    }
    return ContainsCjk(text) ? L"English" : L"简体中文";
}

std::string UrlEncode(const std::string& value) {
    static const wchar_t* hex = L"0123456789ABCDEF";
    std::string result;
    for (unsigned char ch : value) {
        if ((ch >= 'a' && ch <= 'z')
            || (ch >= 'A' && ch <= 'Z')
            || (ch >= '0' && ch <= '9')
            || ch == '-' || ch == '_' || ch == '.' || ch == '~') {
            result.push_back(static_cast<char>(ch));
        } else {
            result.push_back('%');
            result.push_back(static_cast<char>(hex[ch >> 4]));
            result.push_back(static_cast<char>(hex[ch & 0x0F]));
        }
    }
    return result;
}

std::string Md5Hex(const std::string& value) {
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    DWORD objectLength = 0;
    DWORD hashLength = 0;
    DWORD returned = 0;
    std::vector<BYTE> object;
    std::vector<BYTE> digest;

    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_MD5_ALGORITHM, nullptr, 0) < 0) {
        return {};
    }
    BCryptGetProperty(
        algorithm,
        BCRYPT_OBJECT_LENGTH,
        reinterpret_cast<PUCHAR>(&objectLength),
        sizeof(objectLength),
        &returned,
        0
    );
    BCryptGetProperty(
        algorithm,
        BCRYPT_HASH_LENGTH,
        reinterpret_cast<PUCHAR>(&hashLength),
        sizeof(hashLength),
        &returned,
        0
    );
    object.resize(objectLength);
    digest.resize(hashLength);

    if (BCryptCreateHash(
            algorithm,
            &hash,
            object.data(),
            objectLength,
            nullptr,
            0,
            0) < 0) {
        BCryptCloseAlgorithmProvider(algorithm, 0);
        return {};
    }

    BCryptHashData(
        hash,
        reinterpret_cast<PUCHAR>(const_cast<char*>(value.data())),
        static_cast<ULONG>(value.size()),
        0
    );
    BCryptFinishHash(hash, digest.data(), hashLength, 0);
    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(algorithm, 0);

    static const wchar_t* hex = L"0123456789abcdef";
    std::string result;
    for (BYTE byte : digest) {
        result.push_back(static_cast<char>(hex[byte >> 4]));
        result.push_back(static_cast<char>(hex[byte & 0x0F]));
    }
    return result;
}

HttpResult HttpRequest(
    const std::wstring& url,
    const std::wstring& method,
    const std::wstring& contentType,
    const std::string& body,
    const std::wstring& bearer
) {
    HttpResult result;

    URL_COMPONENTS components{};
    components.dwStructSize = sizeof(components);
    components.dwHostNameLength = static_cast<DWORD>(-1);
    components.dwUrlPathLength = static_cast<DWORD>(-1);
    components.dwExtraInfoLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(url.c_str(), static_cast<DWORD>(url.size()), 0, &components)) {
        return result;
    }

    const std::wstring host(components.lpszHostName, components.dwHostNameLength);
    std::wstring path(components.lpszUrlPath, components.dwUrlPathLength);
    if (components.dwExtraInfoLength > 0) {
        path.append(components.lpszExtraInfo, components.dwExtraInfoLength);
    }

    HINTERNET session = WinHttpOpen(
        L"Mote/0.3",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0
    );
    if (!session) {
        return result;
    }
    WinHttpSetTimeouts(session, 10000, 15000, 30000, 30000);

    HINTERNET connection = WinHttpConnect(session, host.c_str(), components.nPort, 0);
    if (!connection) {
        WinHttpCloseHandle(session);
        return result;
    }

    const bool secure = components.nScheme == INTERNET_SCHEME_HTTPS;
    HINTERNET request = WinHttpOpenRequest(
        connection,
        method.c_str(),
        path.c_str(),
        nullptr,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        secure ? WINHTTP_FLAG_SECURE : 0
    );
    if (!request) {
        WinHttpCloseHandle(connection);
        WinHttpCloseHandle(session);
        return result;
    }

    std::wstring headers = L"Content-Type: " + contentType + L"\r\nAccept: application/json\r\n";
    if (!bearer.empty()) {
        headers += L"Authorization: Bearer " + bearer + L"\r\n";
    }

    const BOOL sent = WinHttpSendRequest(
        request,
        headers.c_str(),
        static_cast<DWORD>(-1),
        body.empty() ? nullptr : const_cast<char*>(body.data()),
        static_cast<DWORD>(body.size()),
        static_cast<DWORD>(body.size()),
        0
    );

    if (sent && WinHttpReceiveResponse(request, nullptr)) {
        DWORD status = 0;
        DWORD size = sizeof(status);
        WinHttpQueryHeaders(
            request,
            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            WINHTTP_HEADER_NAME_BY_INDEX,
            &status,
            &size,
            WINHTTP_NO_HEADER_INDEX
        );
        result.status = static_cast<int>(status);

        DWORD available = 0;
        while (WinHttpQueryDataAvailable(request, &available) && available > 0) {
            std::string chunk(available, '\0');
            DWORD read = 0;
            if (!WinHttpReadData(request, chunk.data(), available, &read) || read == 0) {
                break;
            }
            result.body.append(chunk.data(), read);
        }
    }

    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connection);
    WinHttpCloseHandle(session);
    return result;
}

std::wstring BaiduTargetCode(const AppConfig& config, const std::wstring& text) {
    const std::wstring target = TargetFor(config, text);
    if (target == L"简体中文") {
        return L"zh";
    }
    if (target == L"繁體中文") {
        return L"cht";
    }
    if (target == L"English") {
        return L"en";
    }
    if (target == L"日本語") {
        return L"jp";
    }
    if (target == L"한국어") {
        return L"kor";
    }
    return ContainsCjk(text) ? L"en" : L"zh";
}

std::wstring BaiduMessage(const std::wstring& code, const std::wstring& message) {
    if (code == L"52001") return L"百度翻译请求超时，请重试。";
    if (code == L"52002") return L"百度翻译系统错误，请重试。";
    if (code == L"52003") return L"百度翻译未授权用户，请检查 AppID。";
    if (code == L"54001") return L"百度翻译签名错误，请检查密钥。";
    if (code == L"54003") return L"百度翻译访问频率受限，请稍后再试。";
    if (code == L"54004") return L"百度翻译账户余额不足。";
    if (code == L"54005") return L"百度翻译长文本请求频繁，请稍后再试。";
    if (code == L"58001") return L"百度翻译不支持该语言方向。";
    if (code == L"58002") return L"百度翻译服务已关闭。";
    if (code == L"90107") return L"百度翻译认证未通过。";
    return message.empty() ? L"百度翻译返回错误 " + code : message;
}

}  // namespace

bool TranslateAI(
    const AppConfig& config,
    const std::wstring& text,
    std::wstring& output,
    std::wstring& error
) {
    if (!config.llmEnabled) {
        error = L"AI 翻译未启用。";
        return false;
    }
    if (config.endpoint.empty() || config.model.empty()) {
        error = L"请先配置接口地址和模型。";
        return false;
    }

    const std::wstring target = TargetFor(config, text);
    std::wstring prompt = config.systemPrompt;
    size_t position = 0;
    while ((position = prompt.find(L"{targetLang}", position)) != std::wstring::npos) {
        prompt.replace(position, 12, target);
        position += target.size();
    }

    using namespace winrt::Windows::Data::Json;
    JsonObject root;
    root.SetNamedValue(L"model", JsonValue::CreateStringValue(winrt::hstring(config.model.c_str())));

    JsonArray messages;
    JsonObject systemMessage;
    systemMessage.SetNamedValue(L"role", JsonValue::CreateStringValue(L"system"));
    systemMessage.SetNamedValue(L"content", JsonValue::CreateStringValue(winrt::hstring(prompt.c_str())));
    messages.Append(systemMessage);

    JsonObject userMessage;
    userMessage.SetNamedValue(L"role", JsonValue::CreateStringValue(L"user"));
    userMessage.SetNamedValue(L"content", JsonValue::CreateStringValue(winrt::hstring(text.c_str())));
    messages.Append(userMessage);

    root.SetNamedValue(L"messages", messages);
    root.SetNamedValue(L"stream", JsonValue::CreateBooleanValue(false));
    root.SetNamedValue(L"temperature", JsonValue::CreateNumberValue(config.temperature));

    const std::string body = winrt::to_string(root.Stringify());
    const HttpResult response = HttpRequest(
        NormalizeEndpoint(config.endpoint),
        L"POST",
        L"application/json; charset=utf-8",
        body,
        config.aiKey
    );

    if (response.status < 200 || response.status >= 300) {
        error = L"HTTP " + std::to_wstring(response.status) + L"：" + Truncate(response.body);
        return false;
    }

    try {
        const std::wstring wide = Utf8ToWide(response.body);
        const auto parsed = JsonObject::Parse(winrt::hstring(wide.c_str()));

        if (parsed.HasKey(L"error")) {
            const auto errorObject = parsed.GetNamedObject(L"error");
            if (errorObject.HasKey(L"message")) {
                error = errorObject.GetNamedString(L"message").c_str();
            } else {
                error = L"AI 服务返回错误。";
            }
            return false;
        }

        if (!parsed.HasKey(L"choices")) {
            error = L"AI 返回内容缺少 choices。";
            return false;
        }
        const auto choices = parsed.GetNamedArray(L"choices");
        if (choices.Size() == 0) {
            error = L"AI 没有返回翻译结果。";
            return false;
        }
        const auto message = choices.GetObjectAt(0).GetNamedObject(L"message");
        if (!message.HasKey(L"content")) {
            error = L"AI 返回内容缺少 message.content。";
            return false;
        }
        output = Trim(std::wstring(message.GetNamedString(L"content").c_str()));
        if (output.empty()) {
            error = L"AI 返回内容为空。";
            return false;
        }
        return true;
    } catch (...) {
        error = L"无法解析 AI 返回内容。";
        return false;
    }
}

bool TranslateBaidu(
    const AppConfig& config,
    const std::wstring& text,
    std::wstring& output,
    std::wstring& error
) {
    using namespace winrt::Windows::Data::Json;

    if (!config.baiduEnabled) {
        error = L"百度翻译未启用。";
        return false;
    }
    if (config.baiduAppID.empty() || config.baiduKey.empty()) {
        error = L"请先填写百度翻译 AppID 和密钥。";
        return false;
    }

    const std::string appID = WideToUtf8(config.baiduAppID);
    const std::string secret = WideToUtf8(config.baiduKey);
    const std::string query = WideToUtf8(text);
    const std::string salt = std::to_string(GetTickCount64());
    const std::string sign = Md5Hex(appID + query + salt + secret);
    if (sign.empty()) {
        error = L"无法计算百度翻译签名。";
        return false;
    }

    const std::string to = WideToUtf8(BaiduTargetCode(config, text));
    const std::string form =
        "q=" + UrlEncode(query)
        + "&from=auto&to=" + UrlEncode(to)
        + "&appid=" + UrlEncode(appID)
        + "&salt=" + salt
        + "&sign=" + sign;

    const HttpResult response = HttpRequest(
        L"https://fanyi-api.baidu.com/api/trans/vip/translate",
        L"POST",
        L"application/x-www-form-urlencoded; charset=utf-8",
        form,
        L""
    );

    if (response.status < 200 || response.status >= 300) {
        error = L"HTTP " + std::to_wstring(response.status) + L"：" + Truncate(response.body);
        return false;
    }

    try {
        const std::wstring wide = Utf8ToWide(response.body);
        const auto parsed = JsonObject::Parse(winrt::hstring(wide.c_str()));

        if (parsed.HasKey(L"error_code")) {
            const std::wstring code = parsed.GetNamedString(L"error_code").c_str();
            std::wstring message;
            if (parsed.HasKey(L"error_msg")) {
                message = parsed.GetNamedString(L"error_msg").c_str();
            }
            error = BaiduMessage(code, message);
            return false;
        }

        if (!parsed.HasKey(L"trans_result")) {
            error = L"百度翻译返回内容缺少 trans_result。";
            return false;
        }

        const auto results = parsed.GetNamedArray(L"trans_result");
        std::wstring joined;
        for (uint32_t index = 0; index < results.Size(); ++index) {
            const auto item = results.GetObjectAt(index);
            if (!item.HasKey(L"dst")) {
                continue;
            }
            if (!joined.empty()) {
                joined += L"\n";
            }
            joined += item.GetNamedString(L"dst").c_str();
        }

        output = Trim(joined);
        if (output.empty()) {
            error = L"百度翻译没有返回结果。";
            return false;
        }
        return true;
    } catch (...) {
        error = L"无法解析百度翻译返回内容。";
        return false;
    }
}

bool ListModels(
    const AppConfig& config,
    std::vector<std::wstring>& models,
    std::wstring& error
) {
    models.clear();
    if (config.endpoint.empty()) {
        error = L"请先填写接口地址。";
        return false;
    }

    // 与 NormalizeEndpoint 对齐：去掉已有的 chat/completions 尾巴再挂 /models
    std::wstring base = config.endpoint;
    while (!base.empty() && base.back() == L'/') {
        base.pop_back();
    }
    const std::wstring chatSuffix = L"/chat/completions";
    if (base.size() >= chatSuffix.size()
        && base.compare(base.size() - chatSuffix.size(), chatSuffix.size(), chatSuffix) == 0) {
        base.erase(base.size() - chatSuffix.size());
    }
    if (!(base.size() >= 3 && base.compare(base.size() - 3, 3, L"/v1") == 0)) {
        base += L"/v1";
    }

    const HttpResult response = HttpRequest(
        base + L"/models",
        L"GET",
        L"",
        "",
        config.aiKey
    );
    if (response.status < 200 || response.status >= 300) {
        error = L"HTTP " + std::to_wstring(response.status) + L"：" + Truncate(response.body);
        return false;
    }

    try {
        using namespace winrt::Windows::Data::Json;
        const std::wstring wide = Utf8ToWide(response.body);
        const auto parsed = JsonObject::Parse(winrt::hstring(wide.c_str()));
        if (!parsed.HasKey(L"data")) {
            error = L"返回内容缺少 data 字段。";
            return false;
        }
        const auto data = parsed.GetNamedArray(L"data");
        for (uint32_t index = 0; index < data.Size(); ++index) {
            const auto item = data.GetObjectAt(index);
            if (!item.HasKey(L"id")) {
                continue;
            }
            models.push_back(std::wstring(item.GetNamedString(L"id").c_str()));
        }
        if (models.empty()) {
            error = L"服务没有返回任何模型。";
            return false;
        }
        std::sort(models.begin(), models.end());
        return true;
    } catch (...) {
        error = L"无法解析模型列表。";
        return false;
    }
}
