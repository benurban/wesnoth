#!/bin/bash -xe

# build-android-deps.sh
# Builds all the dependencies for the Android version of Wesnoth.

# Prerequisites:
# * wget is used to download the sources. You can download them yourself (see 
#   SOURCES, at the beginning of the script) to bypass this requirement.
# * The Android SDK must be installed, along with at least one version of the
#   NDK.
# * autoconf
# * make
# * meson
# * ninja
# * perl
# * pkg-config
# * python3
# FIXME: Figure out minimum version numbers.
# FIXME: Find out if anything else is needed.

# Environment variables used by this script and setup-toolchains.py:
# DOWNLOADDIR  Files downloaded by the script will wind up here. The script
#              creates this if it doesn't exist.
#     Default: /tmp/android-dl
# BUILDDIR     Working space for dependencies being built. The script creates
#              this if it doesn't exist.
#     Default: /tmp/android-build
# PREFIXDIR    Built dependencies are staged here, inside subdirectories for
#              each ABI. The script creates this if it doesn't exist.
#     Default: /tmp/android-prefix
# ANDROID_SDK_ROOT
#              Root directory of the Android SDK.
#     Default: /opt/android-sdk-update-manager
# ANDROID_NDK_ROOT
#              Root directory of the Android NDK.
#     Default: $ANDROID_SDK_ROOT/ndk/23.1.7779620
# API          The version of the Android API to use
#     Default: 29
# APP_ABI      A space-separated list of the Android ABIs to include in the
#              build. Use "all" to build all four: armeabi-v7a arm64-v8a
#              x86 x86_64
#     Default: all
# PKG_CONFIG   The path to the pkg-config binary.
#     Default: /usr/bin/pkg-config

for cmd in autoreconf make meson ninja perl python3
do
	if ! which "$cmd" >/dev/null
	then
		echo "ERROR: Could not find $cmd." >&2
		echo "Please ensure it is installed and reachable via your \$PATH" >&2
		exit 1
	fi
done

SOURCES=(
https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
https://ftp.gnu.org/pub/gnu/gettext/gettext-0.21.1.tar.gz
https://sourceforge.net/projects/libpng/files/libpng16/1.6.39/libpng-1.6.39.tar.xz
https://sourceforge.net/projects/freetype/files/freetype2/2.13.2/freetype-2.13.2.tar.xz
https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.bz2
https://github.com/libffi/libffi/releases/download/v3.4.4/libffi-3.4.4.tar.gz
https://download.gnome.org/sources/glib/2.76/glib-2.76.1.tar.xz
https://www.cairographics.org/releases/pixman-0.42.2.tar.gz
https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.xz
https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.14.2.tar.xz
https://www.cairographics.org/releases/cairo-1.16.0.tar.xz
https://github.com/harfbuzz/harfbuzz/releases/download/7.1.0/harfbuzz-7.1.0.tar.xz
https://github.com/fribidi/fribidi/releases/download/v1.0.15/fribidi-1.0.15.tar.xz
https://download.gnome.org/sources/pango/1.50/pango-1.50.14.tar.xz
https://github.com/libsdl-org/SDL/releases/download/release-2.26.4/SDL2-2.26.4.tar.gz
https://www.libsdl.org/projects/SDL_image/release/SDL2_image-2.6.3.tar.gz
https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.xz
https://ftp.osuosl.org/pub/xiph/releases/vorbis/libvorbis-1.3.7.tar.xz
https://github.com/libsdl-org/SDL_mixer/releases/download/release-2.6.3/SDL2_mixer-2.6.3.tar.gz
https://archives.boost.io/release/1.85.0/source/boost_1_85_0.tar.bz2
https://www.openssl.org/source/openssl-3.1.0.tar.gz
https://curl.se/download/curl-8.1.1.tar.xz
)

cd -- "$(dirname "$0")"
ORIGIN="$(pwd)"
: DOWNLOADDIR=${DOWNLOADDIR:=/tmp/android-dl}
: BUILDDIR=${BUILDDIR:=/tmp/android-build}
: PREFIXDIR=${PREFIXDIR:=/tmp/android-prefix}

export DOWNLOADDIR
export BUILDDIR
export PREFIXDIR

python3 ./setup-toolchains.py
. "$PREFIXDIR/globals.env"

mkdir -p -- "$DOWNLOADDIR"
mkdir -p -- "$BUILDDIR"
mkdir -p -- "$PREFIXDIR"

os="$(uname -o)"
if [[ $os == Android ]]
then
	# Limit threading on Android to keep from using more memory than the device
	# can handle
	nproc=1
else
	nproc="$(nproc)"
fi

has_pc () {
	case $1 in
		*SDL2*)    return 1 ;; # Rebuild all SDL packages regardless
		*boost*)    check="lib/libboost_system-*.so" ;;
		*bzip2*)    check="lib/libbz2.a" ;;
		*curl*)     check="lib/pkgconfig/libcurl.pc" ;;
		*freetype*) check="lib/pkgconfig/freetype2.pc" ;;
		*gettext*)  check="bin/gettext" ;;
		*glib*)     check="lib/pkgconfig/glib-2.0.pc" ;;
		*iconv*)    check="lib/libiconv.so" ;;
		*libogg*)   check="lib/pkgconfig/ogg.pc" ;;
		*pcre2*)    check="lib/pkgconfig/libpcre2-8.pc" ;;
		*pixman*)   check="lib/pkgconfig/pixman-1.pc" ;;
		*vorbis*)   check="lib/libvorbis.so" ;;
		*)          check="lib/pkgconfig/${1%-*}.pc" ;;
	esac
	shift
	for abi in "$@"
	do
		# Use ls instead of [[ -f ... ]] to allow wildcards
		# We only care about exit status, so using ls should be safe
		if ! ls "$PREFIXDIR/$abi"/$check >/dev/null 2>&1
		then
			return 1
		fi
	done
	return 0
}

mkdir -p -- "$BUILDDIR/src"
pushd -- "$BUILDDIR/src"
for url in "${SOURCES[@]}"
do
	archive="$(basename "$url")"
	package="${archive%.*.*}"
	# We specifically want $APP_ABI to expand into multiple args,
	# if it contains spaces
	if has_pc "$package" $APP_ABI
	then
		continue
	fi
	if [ ! -d "$package" ]
	then
		if [ ! -f "$DOWNLOADDIR/$archive" ]
		then
			wget -nc -P "$DOWNLOADDIR" -- "$url"
		fi
		tar -xf "$DOWNLOADDIR/$archive"
		if [ -f "$ORIGIN/${package%-*}.patch" ]
		then
			patch="$ORIGIN/${package%-*}.patch"
			patch -d "$package" -p1 -i "$patch"
		fi
		if [ -f "$ORIGIN/${package%-*}.autotools.patch" ]
		then
			patch="$ORIGIN/${package%-*}.autotools.patch"
			pushd -- "$package"
			patch -p1 -i "$patch"
			if [[ $package == *SDL2* ]]
			then
				./autogen.sh
				if [ -f android-project/app/jni/Android.mk ]
				then
					mkdir -p ../SDL2-ndk-build/jni
					cp android-project/app/jni/Android.mk ../SDL2-ndk-build/jni/
					sed -e 's/\b\(APP_ABI *:= *\).*/\1'"$APP_ABI"'/' -e 's/\b\(APP_PLATFORM *= *\).*/\1'"$APP_PLATFORM"'/' < android-project/app/jni/Application.mk > ../SDL2-ndk-build/jni/Application.mk
				fi
				ln -sf "../../$package" "../SDL2-ndk-build/jni/${package%-*}"
			else
				autoreconf
			fi
			popd
		fi
	fi

	if [ -f "$ORIGIN/${package%-*}.config" ]
	then
		extra_flags="$(< "$ORIGIN/${package%-*}.config")"
	elif [[ $package == boost* ]] && [ -f "$ORIGIN/${package%%_*}.config" ]
	then
		extra_flags="$(< "$ORIGIN/${package%%_*}.config")"
	else
		extra_flags=
	fi

	src_dir="$BUILDDIR/src/$package"

	for abi in $APP_ABI
	do
		if has_pc "$package" "$abi"
		then
			continue
		fi
		
		rm -rf -- "$BUILDDIR/$abi"

		. "$PREFIXDIR/$abi/android.env"

		host_arg="--host=$HOST"
		build_arg="--build=$BUILD"
		build_dir="$BUILDDIR/$abi/$package"
		mkdir -p -- "$build_dir"
		if [ -f "$src_dir/configure" ]
		then
			if [[ $package == freetype* && $os == Android ]]
			then
				# My Android build environment messes up freetype's libtool when built
				# in a different directory
				pushd -- "$src_dir"
				make clean || : #Original Makefile doesn't include clean for some reason
				./configure "$host_arg" "$build_arg" --prefix="$PREFIXDIR/$abi" $extra_flags
			else
				pushd -- "$build_dir"
				"$src_dir/configure" "$host_arg" "$build_arg" --prefix="$PREFIXDIR/$abi" $extra_flags
			fi
			make -j"$nproc"
			make install
			popd
			continue
		fi
		if [ -f "$src_dir/Configure" ] # OpenSSL's Perl Configure
		then
			pushd -- "$src_dir"
			if [ -f Makefile ]
			then
				make clean
			fi
			./Configure --prefix="$PREFIXDIR/$abi" $extra_flags "android-$ANDROID_ARCH" "-D__ANDROID_API__=$API"
			make -j"$nproc"
			make install
			popd
			continue
		fi
		if [ -f "$src_dir/meson.build" ]
		then
			meson setup --cross-file "$PREFIXDIR/$abi/android.ini" "$build_dir" "$src_dir" -Dprefix="$PREFIXDIR/$abi" $extra_flags
			ninja -C "$build_dir"
			ninja -C "$build_dir" install
			continue
		fi
		if [ -f "$src_dir/Jamroot" ]
		then
			pushd -- "$src_dir"
			rm -rf ./bin.v2
			if [ ! -f ./b2 ]
			then
				./bootstrap.sh
			fi
			if [[ $ANDROID_ARCH == *arm* ]]
			then
				BCABI="aapcs"
				BOOSTARCH="arm"
			else
				BCABI="sysv"
				BOOSTARCH="x86"
			fi
			./b2 --user-config="$PREFIXDIR/$abi/android.jam" --prefix="$PREFIXDIR/$abi" target-os=android architecture="$BOOSTARCH" address-model="$BITNESS" abi="$BCABI" binary-format=elf install $extra_flags
			popd
			continue
		fi
		if [ -f "$src_dir/Makefile" ] # bzip uses plain Make
		then
			pushd -- "$src_dir"
			make clean
			make -j"$nproc" CC="$CC -fPIC" AR="$AR" RANLIB="$RANLIB" PREFIX="$PREFIXDIR/$abi"
			make install CC="$CC -fPIC" AR="$AR" RANLIB="$RANLIB" PREFIX="$PREFIXDIR/$abi"
			popd
			continue
		fi
		rm -rf -- "$build_dir"
	done
	if [[ $package != *SDL* ]]
	then
		rm -rf -- "$src_dir"
	fi
done
popd

cd -- "$BUILDDIR/src/SDL2-ndk-build"
"$NDK/ndk-build"
for abi in $APP_ABI
do
	cp -- "libs/$abi/"*.so "$PREFIXDIR/$abi/lib/"
done
