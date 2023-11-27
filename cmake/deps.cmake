# project/cmake/deps.cmake

# Check if the deps/Daxa submodule exists by checking whether its CMakeLists.txt is present.
if(NOT EXISTS "${CMAKE_CURRENT_LIST_DIR}/../deps/Daxa/CMakeLists.txt")
    # If the CMakeLists.txt isn't present, I make sure I have git and I make sure the git-submodule of Daxa is downloaded
    # This is relevant for using Daxa as a submodule, which is not necessary for non-developers, but you may want to
    # do it anyways, since it allows you to use the latest version of Daxa (only 2.0 is in the official vcpkg package repo)
    find_package(Git REQUIRED)
    execute_process(COMMAND ${GIT_EXECUTABLE} submodule update --init
        WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/.."
        COMMAND_ERROR_IS_FATAL ANY)
endif()

# And then I include another file which I use to handle my vcpkg specific code
include("${CMAKE_CURRENT_LIST_DIR}/vcpkg.cmake")