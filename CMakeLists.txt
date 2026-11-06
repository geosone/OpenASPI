# SPDX-License-Identifier: GPL-2.0-or-later
#
# CMake build of OpenASPI's native C layer (32/64-bit kernels such as GDOS
# and the GonWare server). The DOS drivers and tools keep their Makefile.
#
# As a subproject (add_subdirectory) it provides the static library
# OpenASPI::native; the parent sets the compiler and flags (freestanding,
# no C library). As a top-level project it also builds the host tests.

cmake_minimum_required(VERSION 3.20)
project(OpenASPI LANGUAGES C)

# Shared with the DOS tools (16-bit OpenWatcom), see common/scsi.
add_library(openaspi_scsi STATIC
  common/scsi/sense.c
  common/scsi/inquiry.c
  common/scsi/block_cdb.c
  common/scsi/wire.c)
target_include_directories(openaspi_scsi PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
add_library(OpenASPI::scsi ALIAS openaspi_scsi)

add_library(openaspi_native STATIC
  common/native/hba.c
  common/native/disk.c
  common/native/sat.c)
target_link_libraries(openaspi_native PUBLIC openaspi_scsi)
target_include_directories(openaspi_native PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
set_target_properties(openaspi_scsi openaspi_native PROPERTIES C_STANDARD 90 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
add_library(OpenASPI::native ALIAS openaspi_native)

if(PROJECT_IS_TOP_LEVEL)
  option(OPENASPI_NATIVE_TESTS "Build the host tests of the native layer" ON)
  if(OPENASPI_NATIVE_TESTS)
    enable_testing()
    foreach(_t openaspi_scsi openaspi_native)
      target_compile_options(${_t} PRIVATE -Wall -Wextra -Werror -pedantic)
    endforeach()
    add_executable(native_test tests/native/native_test.c tests/native/host_stub.c)
    target_link_libraries(native_test PRIVATE OpenASPI::native)
    target_compile_options(native_test PRIVATE -Wall -Wextra)
    set_target_properties(native_test PROPERTIES C_STANDARD 11)
    add_test(NAME native COMMAND native_test)
  endif()
endif()
