cmake_minimum_required(VERSION 3.21)
project(fcitx5-xnheime VERSION 0.1.0 LANGUAGES C CXX)

include(GNUInstallDirs)

find_package(Fcitx5Core 5.1.2 REQUIRED)
find_package(Fcitx5Config 5.1.2 REQUIRED)
find_package(Fcitx5Module REQUIRED COMPONENTS Clipboard)
find_program(CARGO_EXECUTABLE cargo REQUIRED)
find_package(Threads REQUIRED)
include("${FCITX_INSTALL_CMAKECONFIG_DIR}/Fcitx5Utils/Fcitx5CompilerSettings.cmake")

set(XNHEIME_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(XNHEIME_RUST_TARGET_DIR "${CMAKE_BINARY_DIR}/cargo-target")
set(_XNHEIME_DEFAULT_CARGO_PROFILE release)
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(_XNHEIME_DEFAULT_CARGO_PROFILE debug)
endif()
set(XNHEIME_CARGO_PROFILE "${_XNHEIME_DEFAULT_CARGO_PROFILE}" CACHE STRING
    "Cargo profile used for the Rust bridge")
set_property(CACHE XNHEIME_CARGO_PROFILE PROPERTY STRINGS debug release)
if(XNHEIME_CARGO_PROFILE STREQUAL "debug")
    set(XNHEIME_CARGO_PROFILE_ARGS)
elseif(XNHEIME_CARGO_PROFILE STREQUAL "release")
    set(XNHEIME_CARGO_PROFILE_ARGS --release)
else()
    message(FATAL_ERROR "XNHEIME_CARGO_PROFILE must be debug or release")
endif()
set(XNHEIME_RUST_LIBRARY
    "${XNHEIME_RUST_TARGET_DIR}/${XNHEIME_CARGO_PROFILE}/libxnheime_cxx.a")
set(XNHEIME_DICTIONARY_EDITOR
    "${XNHEIME_RUST_TARGET_DIR}/${XNHEIME_CARGO_PROFILE}/xnheime-dict-editor")
set(XNHEIME_DICTIONARY_EDITOR_COMMAND
    "${CMAKE_INSTALL_FULL_LIBEXECDIR}/xnheime-dict-editor" CACHE FILEPATH
    "Dictionary editor executable launched by the addon")
set(XNHEIME_CXX_INCLUDE_DIR "${XNHEIME_RUST_TARGET_DIR}/cxxbridge")
set(XNHEIME_CXX_HEADER
    "${XNHEIME_CXX_INCLUDE_DIR}/xnheime-cxx/src/lib.rs.h")

file(GLOB_RECURSE XNHEIME_RUST_SOURCES CONFIGURE_DEPENDS
    "${XNHEIME_ROOT}/crates/xnheime-core/src/*.rs"
    "${XNHEIME_ROOT}/crates/xnheime-cxx/src/*.rs"
    "${XNHEIME_ROOT}/crates/xnheime-dict-editor/src/*.rs")
file(GLOB_RECURSE XNHEIME_DICTIONARY_SOURCES CONFIGURE_DEPENDS
    "${XNHEIME_ROOT}/data/flypy/*")

add_custom_command(
    OUTPUT "${XNHEIME_RUST_LIBRARY}" "${XNHEIME_CXX_HEADER}"
           "${XNHEIME_DICTIONARY_EDITOR}"
    COMMAND "${CMAKE_COMMAND}" -E env
            "CARGO_TARGET_DIR=${XNHEIME_RUST_TARGET_DIR}"
            "${CARGO_EXECUTABLE}" build --locked
            -p xnheime-cxx -p xnheime-dict-editor
            ${XNHEIME_CARGO_PROFILE_ARGS}
    WORKING_DIRECTORY "${XNHEIME_ROOT}"
    DEPENDS
        ${XNHEIME_RUST_SOURCES}
        ${XNHEIME_DICTIONARY_SOURCES}
        "${XNHEIME_ROOT}/Cargo.toml"
        "${XNHEIME_ROOT}/Cargo.lock"
        "${XNHEIME_ROOT}/crates/xnheime-core/Cargo.toml"
        "${XNHEIME_ROOT}/crates/xnheime-core/build.rs"
        "${XNHEIME_ROOT}/crates/xnheime-cxx/Cargo.toml"
        "${XNHEIME_ROOT}/crates/xnheime-cxx/build.rs"
        "${XNHEIME_ROOT}/crates/xnheime-dict-editor/Cargo.toml"
    COMMENT "Building the xnheime Rust components"
    VERBATIM)

add_custom_target(xnheime-cxx-artifacts DEPENDS
    "${XNHEIME_RUST_LIBRARY}" "${XNHEIME_CXX_HEADER}"
    "${XNHEIME_DICTIONARY_EDITOR}")
add_library(xnheime-cxx STATIC IMPORTED GLOBAL)
set_target_properties(xnheime-cxx PROPERTIES IMPORTED_LOCATION "${XNHEIME_RUST_LIBRARY}")
add_dependencies(xnheime-cxx xnheime-cxx-artifacts)

add_library(xnheime SHARED src/xnheime.cpp)
add_dependencies(xnheime xnheime-cxx-artifacts)
target_compile_features(xnheime PRIVATE cxx_std_17)
target_include_directories(xnheime PRIVATE "${XNHEIME_CXX_INCLUDE_DIR}")
target_compile_definitions(xnheime PRIVATE
    XNHEIME_DICTIONARY_EDITOR_COMMAND="${XNHEIME_DICTIONARY_EDITOR_COMMAND}")
target_link_libraries(xnheime PRIVATE xnheime-cxx Fcitx5::Core Fcitx5::Config
    Fcitx5::Module::Clipboard Threads::Threads ${CMAKE_DL_LIBS} m)
set_target_properties(xnheime PROPERTIES PREFIX "")

configure_file(xnheime-addon.conf.in xnheime-addon.conf @ONLY)
install(TARGETS xnheime DESTINATION "${FCITX_INSTALL_LIBDIR}/fcitx5")
install(PROGRAMS "${XNHEIME_DICTIONARY_EDITOR}"
        DESTINATION "${CMAKE_INSTALL_LIBEXECDIR}")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/xnheime-addon.conf"
        RENAME xnheime.conf DESTINATION "${FCITX_INSTALL_PKGDATADIR}/addon")
install(FILES xnheime.conf DESTINATION "${FCITX_INSTALL_PKGDATADIR}/inputmethod")

include(CTest)
if(BUILD_TESTING)
    add_executable(xnheime-cxx-smoke tests/cxx_smoke.cpp)
    add_dependencies(xnheime-cxx-smoke xnheime-cxx-artifacts)
    target_include_directories(xnheime-cxx-smoke PRIVATE "${XNHEIME_CXX_INCLUDE_DIR}")
    target_link_libraries(xnheime-cxx-smoke PRIVATE xnheime-cxx Threads::Threads
        ${CMAKE_DL_LIBS} m)
    add_test(NAME xnheime-cxx-smoke COMMAND xnheime-cxx-smoke)

    add_executable(xnheime-key-policy-test tests/key_policy_test.cpp)
    target_include_directories(xnheime-key-policy-test PRIVATE src)
    target_compile_features(xnheime-key-policy-test PRIVATE cxx_std_17)
    add_test(NAME xnheime-key-policy-test COMMAND xnheime-key-policy-test)

    add_executable(xnheime-candidate-list-test tests/candidate_list_test.cpp)
    target_include_directories(xnheime-candidate-list-test PRIVATE src)
    target_compile_features(xnheime-candidate-list-test PRIVATE cxx_std_17)
    target_link_libraries(xnheime-candidate-list-test PRIVATE Fcitx5::Core)
    add_test(NAME xnheime-candidate-list-test COMMAND xnheime-candidate-list-test)

    add_executable(xnheime-paired-text-test tests/paired_text_test.cpp)
    target_include_directories(xnheime-paired-text-test PRIVATE src)
    target_compile_features(xnheime-paired-text-test PRIVATE cxx_std_17)
    target_link_libraries(xnheime-paired-text-test PRIVATE Fcitx5::Core)
    add_test(NAME xnheime-paired-text-test COMMAND xnheime-paired-text-test)
endif()
