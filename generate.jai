AT_COMPILE_TIME :: true;

// Hyperscan directory containing the top-level CMakeLists.txt
SOURCE_PATH   :: "hyperscan-intel";

// CMake build trees go here (one subdirectory per OS)
BUILD_PATH    :: ".build";

LIB_BASE_NAME :: "libhs";

#if AT_COMPILE_TIME {
    #run,stallable {
        set_build_options_dc(.{do_output=false});
        options := get_build_options();
        args := options.compile_time_command_line;
        if !generate_bindings(args) {
            compiler_set_workspace_status(.FAILED);
        }
    }
} else {
    main :: () {
        set_working_directory(path_strip_filename(get_path_of_running_executable()));
        if !generate_bindings(get_command_line_arguments()) {
            exit(1);
        }
    }
}

generate_bindings :: (args: [] string) -> bool {
    compile        := !array_find(args, "-no_compile");
    compile_debug  :=  array_find(args, "-debug");
    build_shared   :=  array_find(args, "-shared");   // libhs.so / .dylib instead of libhs.a

    boost_root: string;
    jobs := max(get_number_of_processors() / 2, 1);   // Hyperscan compiles are RAM-hungry, so keep this lower by default.
    for args {
        if begins_with(it, "-boost=") boost_root = slice(it, 7, it.count - 7);
        if begins_with(it, "-jobs=") {
            n, ok := to_integer(slice(it, 6, it.count - 6));
            if ok && n > 0 jobs = xx n;
        }
    }

    lib_directory: string;
    #if OS == {
        case .WINDOWS;
            log_error("Windows builds are not implemented in this script yet...");
            return false;
        case .LINUX;
            lib_directory = "linux";
        case .MACOS;
            lib_directory = "macos";
        case;
            assert(false);
    }

    if compile {
        build_dir := tprint("%/%", BUILD_PATH, lib_directory);
        make_directory_if_it_does_not_exist(lib_directory, recursive = true);
        make_directory_if_it_does_not_exist(build_dir,     recursive = true);

        configure: [..] string;
        array_add(*configure, "cmake", "-S", SOURCE_PATH, "-B", build_dir);
        array_add(*configure, tprint("-DCMAKE_BUILD_TYPE=%", ifx compile_debug then "Debug" else "Release"));
        array_add(*configure, ifx build_shared then "-DBUILD_SHARED_LIBS=ON" else "-DBUILD_SHARED_LIBS=OFF");
        array_add(*configure, "-DFAT_RUNTIME=OFF");
        array_add(*configure, "-DCMAKE_POSITION_INDEPENDENT_CODE=ON");

        // Hyperscan's CMakeLists declares a very old minimum version, which CMake 4.x rejects.
        array_add(*configure, "-DCMAKE_POLICY_VERSION_MINIMUM=3.5");
        if boost_root.count > 0 {
            array_add(*configure, tprint("-DBOOST_ROOT=%", boost_root));
        }

        success := run(..configure);
        target := ifx build_shared then "hs_shared" else "hs";
        success &&= run("cmake", "--build", build_dir, "--parallel", tprint("%", jobs), "--target", target);

        if !success return false;

        // Copy the result next to the bindings.
        if build_shared {
            pattern := "libhs.so*";
            #if OS == .MACOS {
                pattern = "libhs*.dylib";
            }

            // cp -a keeps the libhs.so -> libhs.so.5 -> libhs.so.5.x.y symlink chain intact
            copy_cmd := tprint("cp -a \"%/lib\"/% \"%\"/", build_dir, pattern, lib_directory);
            if !run("sh", "-c", copy_cmd) return false;

        } else {
            built_lib := tprint("%/lib/%.a", build_dir,     LIB_BASE_NAME);
             dest_lib := tprint("%/%.a",     lib_directory, LIB_BASE_NAME);

            if !copy_file(built_lib, dest_lib) {
                log_error("Could not copy % to %", built_lib, dest_lib);
                return false;
            }
        }
    }

    options: Generate_Bindings_Options;
    {
        using options;

        array_add(*library_search_paths, lib_directory);
        array_add(*libraries, .{filename=LIB_BASE_NAME});

        // hs.h only #includes these three, so list them directly.
        array_add(*source_files, tprint("%/src/hs_common.h",  SOURCE_PATH));
        array_add(*source_files, tprint("%/src/hs_compile.h", SOURCE_PATH));
        array_add(*source_files, tprint("%/src/hs_runtime.h", SOURCE_PATH));
        array_add(*extra_clang_arguments, "-I", tprint("%/src", SOURCE_PATH));

        generate_library_declarations = false;
        footer = tprint(
            ifx build_shared then FOOTER_SHARED else FOOTER_STATIC,
            to_lower_copy(LIB_BASE_NAME), LIB_BASE_NAME
        );

        log_stripped_declarations = false;
        generate_compile_time_struct_checks = false;

        visitor = hyperscan_visitor;
    }

    output_filename := "bindings.jai";
    return generate_bindings(options, output_filename);
}

DECLARATIONS_TO_OMIT :: string.[
    // Noise ...
    "HS_PUBLIC_API",
    "HS_CDECL",
];


hyperscan_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {
    if !parent_decl {
        if array_find(DECLARATIONS_TO_OMIT, decl.name) {
            decl.decl_flags |= .OMIT_FROM_OUTPUT;
            return .STOP;
        }
    }

    return .RECURSE;
}

run :: (command: .. string, working_directory := "") -> bool {
    result, output_string, error_string := run_command(..command, working_directory = working_directory, capture_and_return_output = true, print_captured_output = true);
    defer {
        free(output_string);
        free(error_string);
    }
    if result.exit_code != 0 {
        log_error("Could not run command \"%\" in directory \"%\". Exit code: %\nError:\n%", get_quoted_command_string(command), working_directory, result.exit_code, error_string);
        return false;
    }
    return true;
}

// libhs.a is C++ and uses OpenSSL, and a static archive doesn't carry those dependencies...
// link_always stops JAI from dropping libraries that no foreign procedure references directly.
FOOTER_STATIC :: #string END

#if OS == .LINUX {
    %1 :: #library,no_dll "linux/%2";
    libstdcpp :: #system_library,link_always "libstdc++";
    libcrypto :: #system_library,link_always "libcrypto";
    libm      :: #system_library,link_always "libm";
    libgcc_s  :: #system_library,link_always "libgcc_s";
} else #if OS == .MACOS {
    %1 :: #library,no_dll "macos/%2";
    libcpp    :: #system_library,link_always "libc++";
    libcrypto :: #system_library,link_always "libcrypto";
} else {
    #assert false;
}

END

// The shared lib records its own dependencies (libstdc++, libcrypto, ...), so none are listed here.
FOOTER_SHARED :: #string END

#if OS == .LINUX {
    %1 :: #library "linux/%2";
} else #if OS == .MACOS {
    %1 :: #library "macos/%2";
} else {
    #assert false;
}

END

#import "Basic";
#import "Bindings_Generator";
#import "Compiler";
#import "System";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
