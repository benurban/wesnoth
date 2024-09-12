#!/usr/bin/env python3
import json
from subprocess import run
from pathlib import Path
from os import environ

sdk = Path(environ.get("ANDROID_SDK_ROOT", environ.get("ANDROID_SDK", "/opt/android-sdk-update-manager")))
ndk = Path(environ.get("ANDROID_NDK_ROOT", environ.get("ANDROID_NDK_HOME", sdk / "ndk/23.1.7779620")))
selected_abis = environ.get("APP_ABI", "all")
api = environ.get("API", 29)
toolchain_os_arch = "linux-x86_64"
pkg_config = Path(environ.get("PKG_CONFIG", "/usr/bin/pkg-config"))
prefix = Path(environ.get("PREFIXDIR", "/tmp/android-prefix"))

abis = json.load(open(ndk / "meta/abis.json"))
if selected_abis == "all":
    abi_list = abis.keys()
else:
    abi_list = selected_abis.split()
app_abi = " ".join(abi_list)

prefix.mkdir(parents = True, exist_ok = True)
with open(prefix / "globals.env", "w") as envfile:
    envfile.write(f"""
export NDK="{ndk}"
export ANDROID_SDK_ROOT="{sdk}"
export ANDROID_NDK_ROOT="{ndk}"
export APP_ABI="{app_abi}"
export TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/{toolchain_os_arch}"
export PATH="$TOOLCHAIN/bin:$PATH"

export API={api}
export APP_PLATFORM=android-$API

export AR="$TOOLCHAIN/bin/llvm-ar"
export LD="$TOOLCHAIN/bin/ld"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export PKG_CONFIG="{pkg_config}"
""")

for abi, abi_data in abis.items():
    if abi not in abi_list:
        continue
    triple = abi_data["llvm_triple"]
    tool_prefix = abi_data["triple"].replace('arm-', 'armv7a-') + str(api) + '-'
    arch = abi_data["arch"]
    abi_prefix = prefix / abi
    abi_prefix.mkdir(parents = True, exist_ok = True)
    with open(abi_prefix / "android.env", "w") as envfile:
        envfile.write(f"""
export ANDROID_ARCH={arch}
export BITNESS={abi_data["bitness"]}

export TARGET={triple}
export HOST={abi_data["triple"]}

export CFLAGS="-target $TARGET$API"
export ASFLAGS="-target $TARGET$API"
export CXXFLAGS="-target $TARGET$API"
export LDFLAGS="-target $TARGET$API -Wl,--undefined-version"

export CC="$TOOLCHAIN/bin/{tool_prefix}clang"
export AS="$CC"
export CXX="$TOOLCHAIN/bin/{tool_prefix}clang++"

export PKG_CONFIG_LIBDIR="{abi_prefix}/lib/pkgconfig"
export PKG_CONFIG_PATH="{abi_prefix}/lib/pkgconfig"

export BUILD="$(cc -dumpmachine || \"$CC\" -dumpmachine)"
""")

    with open(abi_prefix / "android.ini", "w") as crossfile:
        crossfile.write(f"""
[constants]
ndk_home = '{ndk}'
toolchain = ndk_home / 'toolchains/llvm/prebuilt/{toolchain_os_arch}'
target = '{triple}'
api = '{api}'
common_flags = ['-target', target + api]
prefix = '{abi_prefix}'

[host_machine]
system = 'android'
cpu = '{arch}'
cpu_family = '{arch}'
endian = 'little'

[properties]
pkg_config_libdir = '{abi_prefix}' / 'lib/pkgconfig'

[built-in options]
libdir = prefix / 'lib'
includedir = prefix / 'include'
c_args = common_flags + ['-I' + includedir]
cpp_args = common_flags + ['-I' + includedir]
c_link_args = common_flags + ['-L' + libdir]
cpp_link_args = common_flags + ['-L' + libdir]

[binaries]
ar = toolchain / 'bin/llvm-ar'
c = toolchain / 'bin' / 'clang'
cxx = toolchain / 'bin' / 'clang++'
ld = toolchain / 'bin/ld'
ranlib = toolchain / 'bin/llvm-ranlib'
strip = toolchain / 'bin/llvm-strip'
""")
    with open(abi_prefix / "android.jam", "w") as jamfile:
        jamfile.write(f"""
using clang : android
: {ndk}/toolchains/llvm/prebuilt/{toolchain_os_arch}/bin/clang++
: <compileflags>"--target={triple}{api}" <linkflags>"--target={triple}{api}"
<compileflags>-I{abi_prefix}/include <linkflags>-L{abi_prefix}/lib
;
""")
