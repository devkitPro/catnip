
set(CATNIP_RESERVED_IDENTIFIERS all build install clean)

function(__catnip_check_identifier id)
	string(REGEX REPLACE "[a-zA-Z0-9_]" "" invalidchars "${id}")
	if(NOT "${invalidchars}" STREQUAL "")
		message(FATAL_ERROR "Identifier contains an invalid character: ${id}")
	endif()

	string(FIND "${id}" "__" badseq)
	if(badseq GREATER_EQUAL 0)
		message(FATAL_ERROR "Identifier contains a reserved sequence: ${id}")
	endif()

	if("${id}" IN_LIST CATNIP_RESERVED_IDENTIFIERS)
		message(FATAL_ERROR "Reserved identifier: ${id}")
	endif()
endfunction()

function(__catnip_check_identifier2 id)
	string(REGEX REPLACE "[a-zA-Z0-9_-]" "" invalidchars "${id}")
	if(NOT "${invalidchars}" STREQUAL "")
		message(FATAL_ERROR "Identifier2 contains an invalid character: ${id}")
	endif()
endfunction()

macro(__catnip_scope var)
	get_property(${var} GLOBAL PROPERTY CATNIP_SCOPE)
	if(NOT ${var})
		message(FATAL_ERROR "catnip: missing catnip_package() call")
	endif()
endmacro()

function(__catnip_find_root)
	set(dir "")
	set(nextdir "${CMAKE_SOURCE_DIR}")
	while(NOT "${dir}" STREQUAL "${nextdir}")
		set(dir "${nextdir}")

		if(EXISTS "${dir}/.catnip_root")
			set(CATNIP_ROOT "${dir}" PARENT_SCOPE)
			return()
		endif()

		get_filename_component(nextdir "${dir}" DIRECTORY)
	endwhile(NOT "${dir}" STREQUAL "${nextdir}")

	set(CATNIP_ROOT "${CMAKE_SOURCE_DIR}" PARENT_SCOPE)
endfunction()

function(__catnip_find_toolchain var toolchain)
	foreach(dir IN LISTS CMAKE_MODULE_PATH)
		set(file "${dir}/${toolchain}.cmake")
		if(EXISTS "${file}")
			set(${var} "${file}" PARENT_SCOPE)
			return()
		endif()
	endforeach()

	message(FATAL_ERROR "Could not find a suitable '${toolchain}' toolchain")
endfunction()

function(__catnip_add_subdirectory subdir)
	get_filename_component(subdir "${subdir}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_LIST_DIR}")

	include(${subdir}/Catnip.cmake OPTIONAL RESULT_VARIABLE ret)
	if(ret)
		return()
	endif()

	if(EXISTS ${subdir}/CMakeLists.txt)
		file(READ ${subdir}/CMakeLists.txt listtext)
		if(listtext MATCHES "catnip_package")
			include(${subdir}/CMakeLists.txt)
		elseif(DEFINED CATNIP_DEFAULT_TOOLCHAIN)
			get_filename_component(pkgname "${subdir}" NAME)
			__catnip_simple_package(${pkgname} ${subdir} ${CATNIP_DEFAULT_TOOLCHAIN})
		else()
			message(FATAL_ERROR "${subdir} is a valid CMake project, however no toolchain was specified")
		endif()
		return()
	endif()

	#include(${subdir}/CMakeLists.txt OPTIONAL RESULT_VARIABLE ret)
	#if(ret)
	#	return()
	#endif()

	message(FATAL_ERROR "Missing Catnip.cmake or CMakeLists.txt in ${subdir}")
endfunction()

function(catnip_add_subdirectory subdir)
	get_property(backupscope GLOBAL PROPERTY CATNIP_SCOPE)
	set_property(GLOBAL PROPERTY CATNIP_SCOPE "")
	__catnip_add_subdirectory("${subdir}")
	set_property(GLOBAL PROPERTY CATNIP_SCOPE ${backupscope})
endfunction()

function(catnip_package pkgname)
	__catnip_check_identifier("${pkgname}")
	cmake_parse_arguments(PARSE_ARGV 1 ARG
		""
		"DIR"
		"DEFAULT"
	)

	if(NOT ARG_DIR)
		set(ARG_DIR "${CMAKE_CURRENT_LIST_DIR}")
	else()
		get_filename_component(ARG_DIR "${ARG_DIR}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_LIST_DIR}")
	endif()

	if(NOT EXISTS "${ARG_DIR}/CMakeLists.txt")
		message(FATAL_ERROR "Missing CMakeLists.txt in ${pkgname}")
	endif()

	set(scope CATNIP_${pkgname})
	set_property(GLOBAL PROPERTY CATNIP_SCOPE ${scope})
	set_property(GLOBAL APPEND PROPERTY CATNIP_PACKAGES ${pkgname})
	set_property(GLOBAL PROPERTY ${scope}_SOURCE "${ARG_DIR}")
	set_property(GLOBAL PROPERTY ${scope}_DEFAULT "${ARG_DEFAULT}")

	if("${ARG_DIR}" STREQUAL "${CMAKE_SOURCE_DIR}")
		set_property(GLOBAL PROPERTY CATNIP_CWD_PACKAGE ${pkgname})
	endif()
endfunction()

function(catnip_add_preset presetname)
	__catnip_scope(scope)
	__catnip_check_identifier("${presetname}")
	cmake_parse_arguments(PARSE_ARGV 1 ARG
		""
		"TOOLCHAIN;BUILD_TYPE;SYSTEM;PROCESSOR"
		"CACHE;DEPENDS"
	)

	set(cmakeargs "")

	if(ARG_TOOLCHAIN)
		__catnip_check_identifier2("${ARG_TOOLCHAIN}")
		__catnip_find_toolchain(ARG_TOOLCHAIN "${ARG_TOOLCHAIN}")
		list(APPEND cmakeargs "-DCMAKE_TOOLCHAIN_FILE=${ARG_TOOLCHAIN}")
		#list(APPEND cmakeargs "-DCMAKE_TOOLCHAIN_FILE=${DEVKITPRO}/cmake/${ARG_TOOLCHAIN}.cmake")
	endif()

	if(ARG_BUILD_TYPE)
		__catnip_check_identifier2("${ARG_BUILD_TYPE}")
		list(APPEND cmakeargs "-DCMAKE_BUILD_TYPE=${ARG_BUILD_TYPE}")
	endif()

	if(ARG_SYSTEM)
		__catnip_check_identifier2("${ARG_SYSTEM}")
		list(APPEND cmakeargs "-DCMAKE_SYSTEM_NAME=${ARG_SYSTEM}")
	endif()

	if(ARG_PROCESSOR)
		__catnip_check_identifier2("${ARG_PROCESSOR}")
		list(APPEND cmakeargs "-DCMAKE_SYSTEM_PROCESSOR=${ARG_PROCESSOR}")
	endif()

	foreach(cacheentry IN LISTS ARG_CACHE)
		string(FIND "${cacheentry}" "=" eqpos)
		if(eqpos LESS 0)
			message(FATAL_ERROR "Invalid cache entry: ${cacheentry}")
		endif()
		list(APPEND cmakeargs "-D${cacheentry}")
	endforeach()

	list(SORT cmakeargs)
	string(MD5 stamp "${cmakeargs}")

	set_property(GLOBAL APPEND PROPERTY ${scope}_PRESETS ${presetname})

	set(scope ${scope}__${presetname})
	set_property(GLOBAL PROPERTY ${scope}_STAMP "${stamp}")
	set_property(GLOBAL PROPERTY ${scope}_CMAKE_ARGS "${cmakeargs}")
	set_property(GLOBAL PROPERTY ${scope}_DEPENDS "${ARG_DEPENDS}")
endfunction()

function(__catnip_simple_package pkgname dir toolchain)
	#message(STATUS "${dir} -> ${pkgname}")
	string(TOLOWER "${toolchain}" selprefix)
	catnip_package(${pkgname} DIR ${dir} DEFAULT ${selprefix}_release)
	set(configs Debug Release)
	foreach(config IN LISTS configs)
		string(TOLOWER "${config}" selsuffix)
		catnip_add_preset(${selprefix}_${selsuffix}
			TOOLCHAIN ${toolchain}
			BUILD_TYPE ${config}
		)
	endforeach()
endfunction()

if(NOT DEFINED CATNIP_ROOT)
	if(DEFINED ENV{CATNIP_ROOT})
		set(CATNIP_ROOT $ENV{CATNIP_ROOT})
	else()
		__catnip_find_root()
	endif()
endif()

if(NOT DEFINED CATNIP_BUILD_DIR)
	if(DEFINED ENV{CATNIP_BUILD_DIR})
		set(CATNIP_BUILD_DIR $ENV{CATNIP_BUILD_DIR})
	else()
		set(CATNIP_BUILD_DIR ${CATNIP_ROOT}/build)
	endif()
endif()

if(NOT DEFINED CATNIP_DEFAULT_TOOLCHAIN AND DEFINED ENV{CATNIP_DEFAULT_TOOLCHAIN})
	set(CATNIP_DEFAULT_TOOLCHAIN $ENV{CATNIP_DEFAULT_TOOLCHAIN})
endif()

message(STATUS "Catnip root is ${CATNIP_ROOT}")
catnip_add_subdirectory(${CATNIP_ROOT})
