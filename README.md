# Hyperscan bindings for Jai

Jai bindings for [Hyperscan](https://github.com/intel/hyperscan) v5.4.2, Intel's high-performance multiple regex matching library.

The bindings are generated from Hyperscan's public headers (`hs_common.h`, `hs_compile.h`, `hs_runtime.h`) with Jai's `Bindings_Generator`, and `generate.jai` also builds the library from source using CMake.

v5.4.2 is pinned on purpose, since it is part of the last open-source (BSD) line of Hyperscan.

## Platform support

| Platform        | Status                                                                 |
| --------------- | ---------------------------------------------------------------------- |
| Linux x86-64    | Supported                                                              |
| macOS x86-64    | Intended to work (untested...)                                         |
| ARM (any OS)    | Not supported by Intel Hyperscan. [Vectorscan](https://github.com/VectorCamp/vectorscan) is the fork that adds ARM, but this script does not use it yet. |
| Windows         | Not implemented in `generate.jai` yet                                  |

The library is built with `-march=native`, so **the resulting binary is tuned for the CPU it was built on**.

## Setup

1. Clone the repository with its submodule:

   ```shell
   git submodule update --init --recursive
   ```

2. Install the build requirements:

   * CMake, and a C and C++ compiler
   * [Boost](https://www.boost.org/) headers (1.57 or newer). Only the headers are needed, e.g. `libboost-dev` on Debian/Ubuntu. If they are not in a standard location, pass `-boost=<path>` below.
   * [Ragel](https://www.colm.net/open-source/ragel/) (e.g. the `ragel` package)
   * OpenSSL development files (`libcrypto`), because the static footer links it

3. Build the library and generate the bindings, from this directory:

   ```shell
   jai generate.jai                 # static library (default)
   jai generate.jai - -shared       # shared library instead
   ```

   The first can take several minutes. The library lands in `linux/` (or `macos/`) next to the generated `bindings.jai`.

### `generate.jai` options

Pass these after the `-` that separates them from the compiler's own arguments:

| Option          | Effect                                                                 |
| --------------- | ---------------------------------------------------------------------- |
| `-shared`       | Build `libhs.so` / `libhs.dylib` instead of `libhs.a`                  |
| `-debug`        | Build Hyperscan in Debug mode (default is Release)                     |
| `-no_compile`   | Skip building the library and only regenerate `bindings.jai`           |
| `-boost=<path>` | Passed to CMake as `BOOST_ROOT`                                        |
| `-jobs=<n>`     | Parallel compile jobs. Default is half your cores. Hyperscan compiles use a lot of RAM, so use `-jobs=1` or `-jobs=2` on a machine with not-so-much RAM. |

`bindings.jai` is regenerated on every run, and its footer depends on whether you built static or shared. Run `generate.jai` in the mode you intend to link.

## Using the module

```jai
#import "Hyperscan";
// or #import,dir "modules/Hyperscan";
```

Check the generated `bindings.jai` for the exact names and signatures. A minimal block-mode scan looks like this:

```jai
db:  *hs_database_t;
err: *hs_compile_error_t;
if hs_compile("foo.*bar", HS_FLAG_DOTALL, HS_MODE_BLOCK, null, *db, *err) != HS_SUCCESS {
    print("Hyperscan: %\n", to_string(err.message));
    hs_free_compile_error(err);
    return 0;
}
defer hs_free_database(db);

scratch: *hs_scratch_t;
hs_alloc_scratch(db, *scratch);
defer hs_free_scratch(scratch);

on_match :: (id: u32, from: u64, to: u64, flags: u32, ctx: *void) -> s32 #c_call {
    ctx.(*int).* += 1;
    return 0;  // Keep scanning
}

match_count := 0;
text := "xx foo and bar xx";
hs_scan(db, text.data, xx text.count, 0, scratch, on_match, *match_count);

return match_count;
```

## License and more information

Hyperscan v5.4.2 is released under the [3-clause BSD license](https://github.com/intel/hyperscan/blob/master/LICENSE).

These bindings are released under the [MIT license](https://github.com/vrcamillo/jai-tracy/blob/main/LICENSE).

For library documentation, see the [Hyperscan developer reference](https://intel.github.io/hyperscan/dev-reference/).
