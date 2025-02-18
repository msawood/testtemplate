include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(testtemplate_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(testtemplate_setup_options)
  option(testtemplate_ENABLE_HARDENING "Enable hardening" ON)
  option(testtemplate_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    testtemplate_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    testtemplate_ENABLE_HARDENING
    OFF)

  testtemplate_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR testtemplate_PACKAGING_MAINTAINER_MODE)
    option(testtemplate_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(testtemplate_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(testtemplate_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(testtemplate_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(testtemplate_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(testtemplate_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(testtemplate_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(testtemplate_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(testtemplate_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(testtemplate_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(testtemplate_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(testtemplate_ENABLE_PCH "Enable precompiled headers" OFF)
    option(testtemplate_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(testtemplate_ENABLE_IPO "Enable IPO/LTO" ON)
    option(testtemplate_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(testtemplate_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(testtemplate_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(testtemplate_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(testtemplate_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(testtemplate_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(testtemplate_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(testtemplate_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(testtemplate_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(testtemplate_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(testtemplate_ENABLE_PCH "Enable precompiled headers" OFF)
    option(testtemplate_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      testtemplate_ENABLE_IPO
      testtemplate_WARNINGS_AS_ERRORS
      testtemplate_ENABLE_USER_LINKER
      testtemplate_ENABLE_SANITIZER_ADDRESS
      testtemplate_ENABLE_SANITIZER_LEAK
      testtemplate_ENABLE_SANITIZER_UNDEFINED
      testtemplate_ENABLE_SANITIZER_THREAD
      testtemplate_ENABLE_SANITIZER_MEMORY
      testtemplate_ENABLE_UNITY_BUILD
      testtemplate_ENABLE_CLANG_TIDY
      testtemplate_ENABLE_CPPCHECK
      testtemplate_ENABLE_COVERAGE
      testtemplate_ENABLE_PCH
      testtemplate_ENABLE_CACHE)
  endif()

  testtemplate_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (testtemplate_ENABLE_SANITIZER_ADDRESS OR testtemplate_ENABLE_SANITIZER_THREAD OR testtemplate_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(testtemplate_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(testtemplate_global_options)
  if(testtemplate_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    testtemplate_enable_ipo()
  endif()

  testtemplate_supports_sanitizers()

  if(testtemplate_ENABLE_HARDENING AND testtemplate_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR testtemplate_ENABLE_SANITIZER_UNDEFINED
       OR testtemplate_ENABLE_SANITIZER_ADDRESS
       OR testtemplate_ENABLE_SANITIZER_THREAD
       OR testtemplate_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${testtemplate_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${testtemplate_ENABLE_SANITIZER_UNDEFINED}")
    testtemplate_enable_hardening(testtemplate_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(testtemplate_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(testtemplate_warnings INTERFACE)
  add_library(testtemplate_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  testtemplate_set_project_warnings(
    testtemplate_warnings
    ${testtemplate_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(testtemplate_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    testtemplate_configure_linker(testtemplate_options)
  endif()

  include(cmake/Sanitizers.cmake)
  testtemplate_enable_sanitizers(
    testtemplate_options
    ${testtemplate_ENABLE_SANITIZER_ADDRESS}
    ${testtemplate_ENABLE_SANITIZER_LEAK}
    ${testtemplate_ENABLE_SANITIZER_UNDEFINED}
    ${testtemplate_ENABLE_SANITIZER_THREAD}
    ${testtemplate_ENABLE_SANITIZER_MEMORY})

  set_target_properties(testtemplate_options PROPERTIES UNITY_BUILD ${testtemplate_ENABLE_UNITY_BUILD})

  if(testtemplate_ENABLE_PCH)
    target_precompile_headers(
      testtemplate_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(testtemplate_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    testtemplate_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(testtemplate_ENABLE_CLANG_TIDY)
    testtemplate_enable_clang_tidy(testtemplate_options ${testtemplate_WARNINGS_AS_ERRORS})
  endif()

  if(testtemplate_ENABLE_CPPCHECK)
    testtemplate_enable_cppcheck(${testtemplate_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(testtemplate_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    testtemplate_enable_coverage(testtemplate_options)
  endif()

  if(testtemplate_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(testtemplate_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(testtemplate_ENABLE_HARDENING AND NOT testtemplate_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR testtemplate_ENABLE_SANITIZER_UNDEFINED
       OR testtemplate_ENABLE_SANITIZER_ADDRESS
       OR testtemplate_ENABLE_SANITIZER_THREAD
       OR testtemplate_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    testtemplate_enable_hardening(testtemplate_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
