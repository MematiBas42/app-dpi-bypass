cmake_minimum_required(VERSION 3.18)
project(app_dpi_zygisk LANGUAGES C CXX ASM)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_STANDARD 11)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -w -O3 -fvisibility=hidden -fomit-frame-pointer")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -w -O3 -fvisibility=hidden -fvisibility-inlines-hidden -fomit-frame-pointer")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--exclude-libs,ALL -Wl,--undefined-version -Wl,--allow-multiple-definition")

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/dobby/include
)

if(ANDROID_ABI STREQUAL "armeabi-v7a")
    add_definitions(-D__arm__)
    set(LIB_OUTPUT_NAME "armeabi-v7a")
else()
    add_definitions(-D__aarch64__)
    set(LIB_OUTPUT_NAME "arm64-v8a")
endif()

add_library(app_dpi_zygisk SHARED
    main.cpp
)

target_link_libraries(app_dpi_zygisk
    ${CMAKE_CURRENT_SOURCE_DIR}/dobby/lib/${ANDROID_ABI}/libdobby.a
    log
)

set_target_properties(app_dpi_zygisk PROPERTIES OUTPUT_NAME "${LIB_OUTPUT_NAME}")
