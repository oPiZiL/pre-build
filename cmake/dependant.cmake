# get git hash
macro(GetGitHash _git_hash)   # 宏的开始       
  execute_process(          # 执行一个子进程
    COMMAND git rev-parse --short HEAD # 命令
    OUTPUT_VARIABLE ${_git_hash}        # 输出字符串存入变量
    OUTPUT_STRIP_TRAILING_WHITESPACE    # 删除字符串尾的换行符
    ERROR_QUIET                         # 对执行错误静默
    WORKING_DIRECTORY                   # 执行路径
      ${CMAKE_CURRENT_SOURCE_DIR}
  )
endmacro()                      

# 提取版本号
macro(ExtractVersion _project_name)
  string(TOUPPER ${_project_name} PROJECT_NAME_CAP)
  GetGitHash(GITHASH)
  # read CHANGELOG.md and parse the version/build number
  # https://stackoverflow.com/questions/47066115/cmake-get-version-from-multiline-text-file
  file(READ "${CMAKE_CURRENT_SOURCE_DIR}/CHANGELOG.md" CHANGELOG)

  string(REGEX MATCH "\\[([0-9]+\\.[0-9]+\\.[0-9]+)\\]" _ ${CHANGELOG})
  set(${PROJECT_NAME_CAP}_VERSION ${CMAKE_MATCH_1} CACHE INTERNAL "Full package version." FORCE)
  message(STATUS "${_project_name} Version ${${PROJECT_NAME_CAP}_VERSION}.${GITHASH}")

  # 增加版本号的宏定义
  string(REPLACE "." ";" _version_numbers ${${PROJECT_NAME_CAP}_VERSION})
  list(GET _version_numbers 0 ${PROJECT_NAME_CAP}_VERSION_MAJOR)
  list(GET _version_numbers 1 ${PROJECT_NAME_CAP}_VERSION_MINOR)
  list(GET _version_numbers 2 ${PROJECT_NAME_CAP}_VERSION_REVISION)
 
  add_definitions(-D${PROJECT_NAME_CAP}_GIT_HASH_STR=\"${GITHASH}\")
  add_definitions(-D${PROJECT_NAME_CAP}_VERSION_STR=\"${${PROJECT_NAME_CAP}_VERSION}\")
  add_definitions(-D${PROJECT_NAME_CAP}_VERSION_MAJOR=${${PROJECT_NAME_CAP}_VERSION_MAJOR})
  add_definitions(-D${PROJECT_NAME_CAP}_VERSION_MINOR=${${PROJECT_NAME_CAP}_VERSION_MINOR})
  add_definitions(-D${PROJECT_NAME_CAP}_VERSION_REVISION=${${PROJECT_NAME_CAP}_VERSION_REVISION})

  set(DEPLOY_URL "http://mirrors.aubo-robotics.cn:8001/deploy")
  include(FetchContent)
endmacro()

# 添加依赖库
macro(AddDependant _dep_name)
  # FetchContent_MakeAvailable会将名称变为小写
  string(TOLOWER ${_dep_name} DEP_NAME_LOWER)
  cmake_parse_arguments(${_dep_name}
    ""
    "VERSION;TARGET;SYMBOLIC_NAME;URL;GIT_REPOSITORY;GIT_TAG;PATH"
    "INCLUDE_DIRS;STATIC_LIBRARIES;DYNAMIC_LIBRARIES;MODULES;PRIVATE_HEADERS;PUBLIC_HEADERS;RESOURCES;BINARY_RESOURCES"
    ${ARGN}
  )

  if(${_dep_name}_PATH)
    set(FETCHCONTENT_BASE_DIR ${${_dep_name}_PATH})
  else()
    set(FETCHCONTENT_BASE_DIR ${CMAKE_BINARY_DIR}/_deps)
  endif()
  
  if(${_dep_name}_URL)
    set(${_dep_name}_FULLURL ${${_dep_name}_URL})
    FetchContent_Declare(
      ${_dep_name}
      URL  ${${_dep_name}_FULLURL}
    )
  elseif(${_dep_name}_GIT_REPOSITORY)
    set(${_dep_name}_FULLURL ${${_dep_name}_GIT_REPOSITORY})
    FetchContent_Declare(
      ${_dep_name}
      GIT_REPOSITORY  ${${_dep_name}_GIT_REPOSITORY}
      GIT_TAG  ${${_dep_name}_GIT_TAG}
    )
  elseif(DEPLOY_URL)
    set(${_dep_name}_FULLURL ${DEPLOY_URL}/${_dep_name}-${${_dep_name}_VERSION}.zip)
    FetchContent_Declare(
      ${_dep_name}
      URL  ${${_dep_name}_FULLURL}
    )
  else()
    message(FATAL_ERROR "AddDependant: URL is not specified")
  endif()
  message(STATUS "AddDependant: fetch ${${_dep_name}_FULLURL}")

  FetchContent_Populate(${_dep_name})

  # 增加include路径
  if(${_dep_name}_INCLUDE_DIRS)
    message(STATUS "AddDependant: add include path ${${_dep_name}_SOURCE_DIR}/${${_dep_name}_INCLUDE_DIRS}")
    include_directories(${${DEP_NAME_LOWER}_SOURCE_DIR}/${${_dep_name}_INCLUDE_DIRS})
  endif()

  if(${_dep_name}_MODULES)
    set(DEP_MODULE ${${_dep_name}_MODULES})
    message(STATUS "AddDependant: add CMAKE_MODULE_PATH ${${DEP_NAME_LOWER}_SOURCE_DIR}/${${_dep_name}_MODULES}")
    file(GLOB_RECURSE DEP_MODULE_FILE_NAME 
      CONFIGURE_DEPENDS "${${DEP_NAME_LOWER}_SOURCE_DIR}/*${DEP_MODULE}Config.cmake")
    get_filename_component(${DEP_MODULE}_DIR ${DEP_MODULE_FILE_NAME} DIRECTORY)
    find_package(${DEP_MODULE} NO_MODULE REQUIRED)
  endif()

  # 引用库文件(静态)
  if(${_dep_name}_STATIC_LIBRARIES)
    file(GLOB_RECURSE ${_dep_name}_LIBS 
      CONFIGURE_DEPENDS "${${DEP_NAME_LOWER}_SOURCE_DIR}/*${${_dep_name}_STATIC_LIBRARIES}.a")

    if(${_dep_name}_LIBS)
      message(STATUS "AddDependant: link static library ${${_dep_name}_LIBS}")
      link_libraries(${${_dep_name}_LIBS})
    else()
      message(WARNING "AddDependant: cannot find static library ${${_dep_name}_STATIC_LIBRARIES} in ${${DEP_NAME_LOWER}_SOURCE_DIR}/lib")
    endif()
  endif()
  
  # 引用库文件(动态)
  if(${_dep_name}_DYNAMIC_LIBRARIES)
    file(GLOB_RECURSE ${_dep_name}_LIBS 
      CONFIGURE_DEPENDS "${${DEP_NAME_LOWER}_SOURCE_DIR}/*${${_dep_name}_DYNAMIC_LIBRARIES}.so")

    if(${_dep_name}_LIBS)
      message(STATUS "AddDependant: link dynamic library ${${_dep_name}_LIBS}")
      link_libraries(${${_dep_name}_LIBS})
    else()
      message(WARNING "AddDependant: cannot find dynamic library ${${_dep_name}_DYNAMIC_LIBRARIES} in ${${DEP_NAME_LOWER}_SOURCE_DIR}/lib")
    endif()
  endif()
endmacro()

# 打包
function(packageProject)
  include(CMakePackageConfigHelpers)
  include(GNUInstallDirs)

  cmake_parse_arguments(
    PROJECT
    ""
    "NAME;VERSION;INCLUDE_DIR;INCLUDE_DESTINATION;BINARY_DIR;COMPATIBILITY;VERSION_HEADER;NAMESPACE;DISABLE_VERSION_SUFFIX;ARCH_INDEPENDENT"
    "DEPENDENCIES"
    ${ARGN}
  )
  # Use this snippet *after* PROJECT(xxx):
  message(${CMAKE_CURRENT_SOURCE_DIR})
  SET(CMAKE_INSTALL_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}-${PROJECT_VERSION} CACHE PATH "Default CMAKE_INSTALL_PREFIX" FORCE)

  # optional feature: TRUE or FALSE or UNDEFINED! These variables will then hold the respective
  # value from the argument list or be undefined if the associated one_value_keyword could not be
  # found.
  if(PROJECT_DISABLE_VERSION_SUFFIX)
    unset(PROJECT_VERSION_SUFFIX)
  else()
    set(PROJECT_VERSION_SUFFIX -${PROJECT_VERSION})
  endif()

  # handle default arguments:
  if(NOT DEFINED PROJECT_COMPATIBILITY)
    set(PROJECT_COMPATIBILITY AnyNewerVersion)
  endif()

  # we want to automatically add :: to our namespace, so only append if a namespace was given in the
  # first place we also provide an alias to ensure that local and installed versions have the same
  # name
  if(DEFINED PROJECT_NAMESPACE)
    set(PROJECT_NAMESPACE ${PROJECT_NAMESPACE}::)
    add_library(${PROJECT_NAMESPACE}${PROJECT_NAME} ALIAS ${PROJECT_NAME})
  endif()

  if(DEFINED PROJECT_VERSION_HEADER)
    set(PROJECT_VERSION_INCLUDE_DIR ${PROJECT_BINARY_DIR}/PackageProjectInclude)

    string(TOUPPER ${PROJECT_NAME} UPPERCASE_PROJECT_NAME)

    get_target_property(target_type ${PROJECT_NAME} TYPE)
    if(target_type STREQUAL "INTERFACE_LIBRARY")
      set(VISIBILITY INTERFACE)
    else()
      set(VISIBILITY PUBLIC)
    endif()
    target_include_directories(
      ${PROJECT_NAME} ${VISIBILITY} "$<BUILD_INTERFACE:${PROJECT_VERSION_INCLUDE_DIR}>"
    )
    install(
      DIRECTORY ${PROJECT_VERSION_INCLUDE_DIR}/
      DESTINATION ${PROJECT_INCLUDE_DESTINATION}
      COMPONENT "${PROJECT_NAME}_Development"
    )
  endif()

  set(wbpvf_extra_args "")
  if(NOT DEFINED PROJECT_ARCH_INDEPENDENT)
    get_target_property(target_type "${PROJECT_NAME}" TYPE)
    if(TYPE STREQUAL "INTERFACE_LIBRARY")
      set(PROJECT_ARCH_INDEPENDENT YES)
    endif()
  endif()

  if(PROJECT_ARCH_INDEPENDENT)
    set(wbpvf_extra_args ARCH_INDEPENDENT)
  endif()

  install(
    TARGETS ${PROJECT_NAME}
    EXPORT ${PROJECT_NAME}Targets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
            COMPONENT "${PROJECT_NAME}_Runtime"
            NAMELINK_COMPONENT "${PROJECT_NAME}_Development"
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
            COMPONENT "${PROJECT_NAME}_Development"
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
            COMPONENT "${PROJECT_NAME}_Runtime"
    BUNDLE DESTINATION ${CMAKE_INSTALL_BINDIR}
           COMPONENT "${PROJECT_NAME}_Runtime"
    PUBLIC_HEADER DESTINATION ${PROJECT_INCLUDE_DESTINATION} COMPONENT "${PROJECT_NAME}_Development"
    INCLUDES
    DESTINATION "${PROJECT_INCLUDE_DESTINATION}"
  )

  set("${PROJECT_NAME}_INSTALL_CMAKEDIR"
      "${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME}${PROJECT_VERSION_SUFFIX}"
      CACHE PATH "CMake package config location relative to the install prefix"
  )

  mark_as_advanced("${PROJECT_NAME}_INSTALL_CMAKEDIR")

  install(
    DIRECTORY ${PROJECT_INCLUDE_DIR}/
    DESTINATION ${PROJECT_INCLUDE_DESTINATION}
    COMPONENT "${PROJECT_NAME}_Development"
  )
endfunction()
