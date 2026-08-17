#!/usr/bin/env bash
#
# ReactOS Build Environment for Unix-based Operating Systems - Source fetcher for the Base package
# Copyright 2026 RosBE contributors
#
# Released under GNU GPL v2 or any later version.

set -eE

shopt -s dotglob nullglob

#
# Get the absolute path to the script directory
#
cd "$(dirname "$0")"
rs_scriptdir="$PWD"
rs_reporoot="$(cd "$rs_scriptdir/.." && pwd)"

#
# Configuration
#
rs_workdir="${ROSBE_FETCH_WORKDIR:-$rs_scriptdir/.fetch-sources-work}"
rs_downloads_dir="$rs_workdir/downloads"
rs_extracts_dir="$rs_workdir/extracts"
rs_sources_dir="$rs_scriptdir/Base-i386/sources"
rs_checksum_file="$rs_workdir/checksums.sha256"
rs_makecmd=""

rs_binutils_archive="binutils-2.34.tar.xz"
rs_binutils_url="https://ftp.gnu.org/gnu/binutils/$rs_binutils_archive"
rs_binutils_sha256="f00b0e8803dc9bab1e2165bd568528135be734df3fabf8d0161828cd56028952"

rs_bison_archive="bison-3.5.4.tar.gz"
rs_bison_url="https://ftp.gnu.org/gnu/bison/$rs_bison_archive"
rs_bison_sha256="c0dd154dfaba63553a892d41dc400c7baa88cc06a1e2e27813fdd503715e4c28"
rs_bison_patch="$rs_reporoot/Patches/bison-3.5-reactos-fix-win32-build.patch"
rs_bison_patch_sha256="1dc81140c60cc69056a5a4bbfe61a874db8ae5cd9f89df72f80f114dfecb9802"

rs_cmake_archive="cmake-3.17.2-07c58033.zip"
rs_cmake_url="https://github.com/reactos/CMake/archive/07c58033.zip"
rs_cmake_sha256="243e3d48b1af2bc9db9acab709f702031f15f39124720c2d3dae2d16b73074fb"

rs_flex_archive="flex-2.6.4-8b1fbf67.zip"
rs_flex_url="https://github.com/westes/flex/archive/8b1fbf67.zip"
rs_flex_sha256="1455ecf338ad889e8003aa0dc255f883a3f5c2e97a2ac0bedd9034d333ec6c07"

rs_gcc_archive="gcc-8.4.0.tar.xz"
rs_gcc_url="https://ftp.gnu.org/gnu/gcc/gcc-8.4.0/$rs_gcc_archive"
rs_gcc_sha256="e30a6e52d10e1f27ed55104ad233c30bd1e99cfb5ff98ab022dc941edd1b2dd4"

rs_gmp_archive="gmp-6.2.0.tar.xz"
rs_gmp_url="https://ftp.gnu.org/gnu/gmp/$rs_gmp_archive"
rs_gmp_sha256="258e6cd51b3fbdfc185c716d55f82c08aff57df0c6fbd143cf6ed561267a1526"
rs_gmp_patch="$rs_reporoot/Patches/GMP-6.2.0-C89-fixes.patch"
rs_gmp_patch_sha256="83652d4cd41efa860dcd7557994c8b9c18e2cc7ba0476dcffd46fa09197fbaf2"

rs_mingw_w64_archive="mingw-w64-v6.0.0.tar.bz2"
rs_mingw_w64_url="https://downloads.sourceforge.net/project/mingw-w64/mingw-w64/mingw-w64-release/$rs_mingw_w64_archive"
rs_mingw_w64_sha256="805e11101e26d7897fce7d49cbb140d7bac15f3e085a91e0001e80b2adaf48f0"

rs_mpc_archive="mpc-1.1.0.tar.gz"
rs_mpc_url="https://ftp.gnu.org/gnu/mpc/$rs_mpc_archive"
rs_mpc_sha256="6985c538143c1208dcb1ac42cedad6ff52e267b47e5f970183a3e75125b43c2e"

rs_mpfr_archive="mpfr-4.0.2.tar.xz"
rs_mpfr_url="https://www.mpfr.org/mpfr-4.0.2/$rs_mpfr_archive"
rs_mpfr_sha256="1d3be708604eae0e42d578ba93b390c2a145f17743a744d8f3f8c2ad5855a38a"

rs_ninja_archive="ninja-1.10.0.tar.gz"
rs_ninja_url="https://github.com/ninja-build/ninja/archive/refs/tags/v1.10.0.tar.gz"
rs_ninja_sha256="3810318b08489435f8efc19c05525e80a993af5a55baa0dfeae0465a9d45f99f"

# shellcheck disable=SC1091
# setuplibrary.sh is sourced via the repository-relative runtime path above.
source "$rs_scriptdir/Base-i386/scripts/setuplibrary.sh"


#
# Functions
#
rs_show_failure()
{
	local rs_status=$?

	echo
	rs_redmsg "FAILED"
	echo "Please take a look at the log file \"$rs_workdir/build.log\""
	echo "Aborted!"
	exit "$rs_status"
}

trap rs_show_failure ERR

rs_add_checksum()
{
	printf '%s *%s\n' "$1" "$2" >> "$rs_checksum_file"
}

rs_check_required_tools()
{
	local rs_tool

	echo "Checking for the needed tools..."
	for rs_tool in autoconf automake curl grep help2man patch sha256sum tar unzip xz zip; do
		echo -n "Checking for $rs_tool... "
		if command -v "$rs_tool" >/dev/null 2>&1; then
			rs_greenmsg "OK"
		else
			rs_redmsg "MISSING"
			echo "At least one needed tool is missing, aborted!"
			exit 1
		fi
	done

	echo -n "Checking for GNU Make... "
	for rs_tool in make gmake; do
		if command -v "$rs_tool" >/dev/null 2>&1 && "$rs_tool" -v 2>&1 | grep "GNU Make" >/dev/null; then
			rs_makecmd="$rs_tool"
			rs_greenmsg "OK"
			echo
			return 0
		fi
	done

	rs_redmsg "MISSING"
	echo "At least one needed tool is missing, aborted!"
	exit 1
}

rs_download_archive()
{
	local rs_name="$1"
	local rs_url="$2"
	local rs_archive="$3"
	local rs_sha256="$4"

	echo "Downloading $rs_name..."
	curl \
		--fail \
		--location \
		--retry 3 \
		--retry-all-errors \
		--retry-delay 10 \
		--output "$rs_downloads_dir/$rs_archive" \
		"$rs_url" >> "$rs_workdir/build.log" 2>&1

	rs_add_checksum "$rs_sha256" "$rs_downloads_dir/$rs_archive"
}

rs_verify_downloads()
{
	echo "Verifying hashes..."
	sha256sum -c "$rs_checksum_file" >> "$rs_workdir/build.log" 2>&1
}

rs_extract_archive()
{
	local rs_archive="$1"
	local rs_target_dir="$2"

	mkdir -p "$rs_target_dir"

	case "$rs_archive" in
		*.zip)
			unzip -q "$rs_archive" -d "$rs_target_dir" >> "$rs_workdir/build.log" 2>&1
			;;
		*)
			tar -C "$rs_target_dir" -xf "$rs_archive" >> "$rs_workdir/build.log" 2>&1
			;;
	esac
}

rs_get_single_directory()
{
	local rs_dir="$1"
	local rs_entries=()

	rs_entries=("$rs_dir"/*)

	if [[ ${#rs_entries[@]} -ne 1 || ! -d "${rs_entries[0]}" ]]; then
		echo "Unexpected archive layout in \"$rs_dir\"" >> "$rs_workdir/build.log"
		return 1
	fi

	printf '%s\n' "${rs_entries[0]}"
}

rs_apply_patch()
{
	local rs_source_dir="$1"
	local rs_patch="$2"

	patch -d "$rs_source_dir" -p1 < "$rs_patch" >> "$rs_workdir/build.log" 2>&1
}

rs_prepare_bison()
{
	local rs_source_dir="$1"

	echo "Patching bison..."
	rs_apply_patch "$rs_source_dir" "$rs_bison_patch"
}

rs_prepare_flex()
{
	local rs_source_dir="$1"
	local rs_dist_dir="$rs_extracts_dir/flex-dist"
	local rs_dist_archive=()
	local rs_extracted_dist

	echo "Running flex autogen.sh..."
	(
		cd "$rs_source_dir"
		rs_do_command ./autogen.sh
	)

	echo "Running flex make dist..."
	(
		cd "$rs_source_dir"
		rs_do_command "$rs_makecmd" dist
	)

	rs_dist_archive=("$rs_source_dir"/flex-*.tar.gz)

	if [[ ${#rs_dist_archive[@]} -ne 1 ]]; then
		echo "Unexpected flex dist output in \"$rs_source_dir\"" >> "$rs_workdir/build.log"
		return 1
	fi

	rm -rf "$rs_dist_dir"
	mkdir -p "$rs_dist_dir"
	tar -C "$rs_dist_dir" -xzf "${rs_dist_archive[0]}" >> "$rs_workdir/build.log" 2>&1
	rs_extracted_dist="$(rs_get_single_directory "$rs_dist_dir")"

	rm -rf "$rs_source_dir"
	mv "$rs_extracted_dist" "$rs_source_dir"
}

rs_prepare_gmp()
{
	local rs_source_dir="$1"

	echo "Patching gmp..."
	rs_apply_patch "$rs_source_dir" "$rs_gmp_patch"
}

rs_pack_source_archive()
{
	local rs_name="$1"
	local rs_source_dir="$2"

	echo "Packing $rs_name..."
	tar -C "$(dirname "$rs_source_dir")" -cjf "$rs_sources_dir/$rs_name.tar.bz2" "$(basename "$rs_source_dir")" >> "$rs_workdir/build.log" 2>&1
}

rs_prepare_source_archive()
{
	local rs_name="$1"
	local rs_archive="$2"
	local rs_prepare_function="${3:-}"
	local rs_extract_dir="$rs_extracts_dir/$rs_name-src"
	local rs_source_dir

	echo "Preparing $rs_name..."
	rm -rf "$rs_extract_dir"
	mkdir -p "$rs_extract_dir"
	rs_extract_archive "$rs_downloads_dir/$rs_archive" "$rs_extract_dir"
	rs_source_dir="$(rs_get_single_directory "$rs_extract_dir")"
	mv "$rs_source_dir" "${rs_extract_dir%%-src}"
	rs_source_dir="${rs_extract_dir%%-src}"
	if [[ -n "$rs_prepare_function" ]]; then
		"$rs_prepare_function" "$rs_source_dir"
	fi
	rs_pack_source_archive "$rs_name" "$rs_source_dir"
}

rs_verify_prepared_archive()
{
	local rs_name="$1"
	local rs_verify_dir="$rs_workdir/verify-$rs_name"
	local rs_top_dir

	echo "Checking $rs_name archive..."
	rm -rf "$rs_verify_dir"
	mkdir -p "$rs_verify_dir"
	tar -C "$rs_verify_dir" -xjf "$rs_sources_dir/$rs_name.tar.bz2" >> "$rs_workdir/build.log" 2>&1
	rs_top_dir="$(rs_get_single_directory "$rs_verify_dir")"

	if [[ "$(basename "$rs_top_dir")" != "$rs_name" ]]; then
		echo "Archive \"$rs_sources_dir/$rs_name.tar.bz2\" extracted to \"$(basename "$rs_top_dir")\" instead of \"$rs_name\"" >> "$rs_workdir/build.log"
		return 1
	fi
}


#
# Prepare the working directories
#
echo "Preparing working directories..."
rm -rf "$rs_workdir"
mkdir -p "$rs_downloads_dir" "$rs_extracts_dir" "$rs_sources_dir"
find "$rs_sources_dir" -mindepth 1 -maxdepth 1 -type f -name '*.tar.bz2' -delete
rm -f "$rs_scriptdir/Base-i386/README.pdf"
: > "$rs_workdir/build.log"
: > "$rs_checksum_file"

rs_check_required_tools


#
# Download the upstream sources and verify all hashes
#
# Each entry: "name|archive|url|sha256|prepare_function"
# prepare_function is optional (empty = no extra preparation step)
#
rs_sources=(
    "binutils|$rs_binutils_archive|$rs_binutils_url|$rs_binutils_sha256|"
    "bison|$rs_bison_archive|$rs_bison_url|$rs_bison_sha256|rs_prepare_bison"
    "cmake|$rs_cmake_archive|$rs_cmake_url|$rs_cmake_sha256|"
    "flex|$rs_flex_archive|$rs_flex_url|$rs_flex_sha256|rs_prepare_flex"
    "gcc|$rs_gcc_archive|$rs_gcc_url|$rs_gcc_sha256|"
    "gmp|$rs_gmp_archive|$rs_gmp_url|$rs_gmp_sha256|rs_prepare_gmp"
    "mingw_w64|$rs_mingw_w64_archive|$rs_mingw_w64_url|$rs_mingw_w64_sha256|"
    "mpc|$rs_mpc_archive|$rs_mpc_url|$rs_mpc_sha256|"
    "mpfr|$rs_mpfr_archive|$rs_mpfr_url|$rs_mpfr_sha256|"
    "ninja|$rs_ninja_archive|$rs_ninja_url|$rs_ninja_sha256|"
)

for rs_entry in "${rs_sources[@]}"; do
    IFS='|' read -r rs_name rs_archive rs_url rs_sha256 rs_prepare <<< "$rs_entry"
    rs_download_archive "$rs_name" "$rs_url" "$rs_archive" "$rs_sha256"
done
rs_add_checksum "$rs_bison_patch_sha256" "$rs_bison_patch"
rs_add_checksum "$rs_gmp_patch_sha256" "$rs_gmp_patch"
rs_verify_downloads


#
# Prepare and repack the RosBE source archives
#
for rs_entry in "${rs_sources[@]}"; do
    IFS='|' read -r rs_name rs_archive rs_url rs_sha256 rs_prepare <<< "$rs_entry"
    rs_prepare_source_archive "$rs_name" "$rs_archive" "$rs_prepare"
done


#
# Create the required README.pdf placeholder
#
echo "Creating README.pdf placeholder..."
printf '%%PDF-1.4\n%%%%EOF\n' > "$rs_scriptdir/Base-i386/README.pdf"


#
# Verify the prepared archives
#
for rs_entry in "${rs_sources[@]}"; do
    IFS='|' read -r rs_name rs_archive rs_url rs_sha256 rs_prepare <<< "$rs_entry"
    rs_verify_prepared_archive "$rs_name"
done

echo
echo "Done."
