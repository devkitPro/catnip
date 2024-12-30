cmake_minimum_required(VERSION 3.13)

set(CATNIP TRUE)
set(CATNIP_VERBS build install clean)

include(${CMAKE_CURRENT_LIST_DIR}/dkp-initialize-path.cmake)
include(Catnip/Utility)
include(Catnip/Information)
include(Catnip/Topology)

if("${CATNIP_VERB}" STREQUAL "build" OR "${CATNIP_VERB}" STREQUAL "install")
	include(Catnip/Verb-Build)
elseif("${CATNIP_VERB}" STREQUAL "clean")
	include(Catnip/Verb-Clean)
endif()
