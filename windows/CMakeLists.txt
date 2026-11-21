cmake_minimum_required(VERSION 3.20)
project(LingoliteWin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(Lingolite WIN32 src/main.cpp)

target_compile_definitions(Lingolite PRIVATE
    UNICODE
    _UNICODE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)

target_link_libraries(Lingolite PRIVATE
    user32
    shell32
    gdi32
    ole32
    winhttp
    uiautomationcore
)

