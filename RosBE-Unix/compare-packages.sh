#!/usr/bin/env bash
#
# ReactOS Build Environment for Unix-based Operating Systems - Package comparison tool
# Copyright 2025 Colin Finck <colin@reactos.org>
#
# Released under GNU GPL v2 or any later version.
#
# Compares a locally-built RosBE-Unix package against a reference package
# (typically the official release), ignoring known expected differences.
#
# Usage: compare-packages.sh <generated-package.tar.bz2> <reference-package.tar.bz2>
#
# Exit status 0 = packages match within expected tolerances.
# Exit status 1 = unexpected differences found.

set -e

#
# Check arguments
#
if [[ $# -ne 2 ]]; then
	echo "compare-packages - Compare a generated RosBE-Unix package against a reference"
	echo "Syntax: ./compare-packages.sh <generated-package> <reference-package>"
	echo
	echo " generated-package  - Package built by makepackage.sh"
	echo " reference-package  - Reference (e.g. the official RosBE-Unix-2.2.1.tar.bz2)"
	exit 1
fi

rs_generated_pkg="$1"
rs_reference_pkg="$2"

if [[ ! -f "$rs_generated_pkg" ]]; then
	echo "ERROR: Generated package not found: $rs_generated_pkg" >&2
	exit 1
fi

if [[ ! -f "$rs_reference_pkg" ]]; then
	echo "ERROR: Reference package not found: $rs_reference_pkg" >&2
	exit 1
fi

#
# Set up a temporary working directory that is removed on exit
#
rs_tmpdir=$(mktemp -d)
trap 'rm -rf "$rs_tmpdir"' EXIT

# Overall pass/fail tracker (set to 1 by rs_compare_source_archive on failure)
rs_failed=0

#
# Compare a source archive by extracting both copies and diffing their contents
#
# Usage: rs_compare_source_archive <name> [<exclude-pattern> ...]
# The name must match the .tar.bz2 basename in sources/ (e.g. "binutils").
# Each exclude pattern is passed to diff --exclude.
#
rs_compare_source_archive()
{
	local name="$1"
	shift
	local diff_args=(-rq)
	local excl
	local gen_archive ref_archive
	local gen_src ref_src
	local gen_top ref_top

	for excl in "$@"; do
		diff_args+=("--exclude=$excl")
	done

	echo "Comparing $name..."

	gen_archive="$rs_gen_dir/sources/$name.tar.bz2"
	ref_archive="$rs_ref_dir/sources/$name.tar.bz2"

	if [[ ! -f "$gen_archive" ]]; then
		echo "  ERROR: $gen_archive not found"
		rs_failed=1
		return
	fi

	if [[ ! -f "$ref_archive" ]]; then
		echo "  ERROR: $ref_archive not found"
		rs_failed=1
		return
	fi

	gen_src="$rs_tmpdir/gen_src/$name"
	ref_src="$rs_tmpdir/ref_src/$name"
	mkdir -p "$gen_src" "$ref_src"

	tar -C "$gen_src" -xjf "$gen_archive"
	tar -C "$ref_src" -xjf "$ref_archive"

	gen_top=$(find "$gen_src" -maxdepth 1 -mindepth 1 -type d | head -1)
	ref_top=$(find "$ref_src" -maxdepth 1 -mindepth 1 -type d | head -1)

	if [[ -z "$gen_top" || -z "$ref_top" ]]; then
		echo "  ERROR: Could not find top-level directory inside $name.tar.bz2"
		rs_failed=1
		return
	fi

	if diff "${diff_args[@]}" "$gen_top" "$ref_top"; then
		echo "  OK"
	else
		echo "  DIFFERENCES FOUND in $name (run diff -r to see full output)"
		rs_failed=1
	fi
}

#
# Extract both packages
#
echo "Extracting generated package: $(basename "$rs_generated_pkg")"
mkdir -p "$rs_tmpdir/generated"
tar -C "$rs_tmpdir/generated" -xjf "$rs_generated_pkg"

echo "Extracting reference package: $(basename "$rs_reference_pkg")"
mkdir -p "$rs_tmpdir/reference"
tar -C "$rs_tmpdir/reference" -xjf "$rs_reference_pkg"

rs_gen_dir=$(find "$rs_tmpdir/generated" -maxdepth 1 -mindepth 1 -type d | head -1)
rs_ref_dir=$(find "$rs_tmpdir/reference" -maxdepth 1 -mindepth 1 -type d | head -1)

if [[ -z "$rs_gen_dir" ]]; then
	echo "ERROR: Could not find top-level directory in generated package" >&2
	exit 1
fi

if [[ -z "$rs_ref_dir" ]]; then
	echo "ERROR: Could not find top-level directory in reference package" >&2
	exit 1
fi

echo "Generated root: $(basename "$rs_gen_dir")"
echo "Reference root: $(basename "$rs_ref_dir")"
echo

#
# Compare source archives
#
# Each call passes the archive name and the per-tool exclusions documented in
# AGENTS.md ("Known Differences Between Automated and Manual RosBE 2.2.1").
# The outer .tar.bz2 compression is not compared — only the extracted contents.
#
echo "=== Comparing source archives ==="

# Binutils: exclude tic80/cr16c targets, doc, testsuite, emulparams, elf32 linker scripts
rs_compare_source_archive "binutils" "*tic80*" "*cr16c*" "doc" "testsuite" "emulparams" "elf32*"

# Bison: no known differences
rs_compare_source_archive "bison"

# CMake: exclude git-related metadata added by the ReactOS cmake fork
# Note: cmake.patch was NOT applied when building the 2.2.1 release, so
# comparison uses the unpatched tree (do not apply cmake.patch before running
# this script).
rs_compare_source_archive "cmake" ".gitattributes" ".github" ".gitignore" ".hooks-config" \
	"CMakeVersion.cmake" "Git" "GitSetup" "SetupForDevelopment.sh"

# Flex: exclude files that differ based on autogen.sh host tool versions
rs_compare_source_archive "flex" "build-aux" "po" "Makefile.in" "configure" "doc" "libtool.m4"

# GCC, GMP, mingw-w64, MPC, MPFR, Ninja: no known differences
rs_compare_source_archive "gcc"
rs_compare_source_archive "gmp"
rs_compare_source_archive "mingw_w64"
rs_compare_source_archive "mpc"
rs_compare_source_archive "mpfr"
rs_compare_source_archive "ninja"

#
# Compare non-source files
#
# Exclude:
#   sources/    - compared archive-by-archive above
#   README.pdf  - generated package uses a placeholder; reference has the real PDF
#
echo
echo "=== Comparing non-source files ==="
echo "Comparing scripts, tools, and other files..."

if diff -rq \
	--exclude="sources" \
	--exclude="README.pdf" \
	"$rs_gen_dir" "$rs_ref_dir"; then
	echo "  OK"
else
	echo "  DIFFERENCES FOUND in non-source files (run diff -r to see full output)"
	rs_failed=1
fi

#
# Report result
#
echo
if [[ "$rs_failed" -ne 0 ]]; then
	echo "FAIL: Unexpected differences found between packages."
	exit 1
fi

echo "PASS: Packages match within expected tolerances."
