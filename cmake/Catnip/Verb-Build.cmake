
function(__catnip_generator var)
	get_property(generator GLOBAL PROPERTY CATNIP_GENERATOR)
	if(NOT generator)
		find_program(PROG_NINJA ninja)
		if(PROG_NINJA)
			set(generator "Ninja")
		else()
			set(generator "Unix Makefiles")
		endif()
		set_property(GLOBAL PROPERTY CATNIP_GENERATOR "${generator}")
	endif()

	set(${var} "${generator}" PARENT_SCOPE)
endfunction()

function(__catnip_build selector)
	string(FIND "${selector}" "." dotpos)
	string(SUBSTRING "${selector}" 0 ${dotpos} pkgname)
	math(EXPR dotpos "${dotpos}+1")
	string(SUBSTRING "${selector}" ${dotpos} -1 preset)
	#string(REPLACE "." "__" scope "${selector}")
	#set(scope CATNIP_${scope})
	set(scope CATNIP_${pkgname}__${preset})

	get_property(srcdir GLOBAL PROPERTY CATNIP_${pkgname}_SOURCE)
	get_property(stamp GLOBAL PROPERTY ${scope}_STAMP)
	set(builddir "${CATNIP_BUILD_DIR}/${selector}")
	set(stampfile "${builddir}/.catnip_stamp")

	if(EXISTS "${stampfile}")
		file(READ "${stampfile}" existingstamp)
		if(NOT "${existingstamp}" STREQUAL "${stamp}")
			message(STATUS "Config for ${selector} changed, deleting stale build dir")
			file(REMOVE_RECURSE "${builddir}")
		endif()
	endif()

	file(MAKE_DIRECTORY "${builddir}")
	message(STATUS "Entering ${builddir}")

	if(NOT EXISTS "${stampfile}")
		get_property(cmakeargs GLOBAL PROPERTY ${scope}_CMAKE_ARGS)
		__catnip_generator(generator)

		execute_process(
			COMMAND ${CMAKE_COMMAND} -E env
				"CATNIP_BUILD_DIR=${CATNIP_BUILD_DIR}"
				"CATNIP_PRESET=${preset}"
				${CMAKE_COMMAND} ${cmakeargs}
				-D CMAKE_EXPORT_COMPILE_COMMANDS:BOOL=TRUE
				#-D DKP_NO_BUILTIN_CMAKE_CONFIGS:BOOL=TRUE
				#-D "CATNIP_BUILD_DIR:PATH=${CATNIP_BUILD_DIR}"
				#-D "CATNIP_PRESET:STRING=${preset}"
				-G "${generator}"
				-S "${srcdir}"
				-B "${builddir}"
			RESULT_VARIABLE error
			OUTPUT_QUIET
		)

		if(error)
			file(REMOVE_RECURSE "${builddir}")
			message(FATAL_ERROR "Failed to configure ${selector}")
		endif()

		file(WRITE "${stampfile}" "${stamp}")
	endif()

	execute_process(
		COMMAND ${CMAKE_COMMAND} --build "${builddir}"
		RESULT_VARIABLE error
	)

	if(error)
		message(FATAL_ERROR "Failed to build ${selector}")
	endif()
endfunction()

foreach(sel IN LISTS CATNIP_SELECTORS)
	__catnip_build("${sel}")
endforeach()
