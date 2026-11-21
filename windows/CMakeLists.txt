cmake_minimum_required(VERSION 3.20)
project(LingoliteWin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(Lingolite WIN32
    src/main.cpp
    src/config.cpp
    src/http.cpp
    src/ocr.cpp
    src/selection.cpp
    resources/resource.rc
)

target_include_directories(Lingolite PRIVATE src resources)

target_compile_options(Lingolite PRIVATE /utf-8)

target_compile_definitions(Lingolite PRIVATE
    UNICODE
    _UNICODE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)

target_link_libraries(Lingolite PRIVATE
    advapi32
    bcrypt
    comctl32
    user32
    shell32
    gdi32
    ole32
    oleaut32
    winhttp
    uiautomationcore
    windowsapp
)

