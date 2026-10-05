# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "pouch_core")
project(${PROJECT_NAME} LANGUAGES CXX)

include("${CMAKE_SOURCE_DIR}/flutter/ephemeral/generated_config.cmake")
include("../cargokit/cmake/cargokit.cmake")
get_filename_component(POUCH_RUST_ROOT "${CMAKE_SOURCE_DIR}/../../rust" ABSOLUTE)
if(NOT EXISTS "${POUCH_RUST_ROOT}/Cargo.toml")
  message(FATAL_ERROR "Pouch Rust manifest not found: ${POUCH_RUST_ROOT}/Cargo.toml")
endif()
apply_cargokit(${PROJECT_NAME} "${POUCH_RUST_ROOT}" pouch_core "")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(pouch_core_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
