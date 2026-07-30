#!/usr/bin/env bash
#
# Compare a generated RosBE-Unix package against a reference package.
# Known differences between automated and official packages are tolerated.
#
# Usage: compare-packages.sh <generated.tar.bz2> <reference.tar.bz2>
# Exit 0 = pass, 1 = fail.

set -e

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

rs_tmpdir=$(mktemp -d)
trap 'rm -rf "$rs_tmpdir"' EXIT

rs_failed=0

#
# Extract both packages, stripping the version-directory prefix so that the
# package contents land directly under $rs_tmpdir/gen and $rs_tmpdir/ref.
#
echo "Extracting packages..."
mkdir -p "$rs_tmpdir/gen" "$rs_tmpdir/ref"
tar --strip-components=1 -C "$rs_tmpdir/gen" -xjf "$rs_generated_pkg"
tar --strip-components=1 -C "$rs_tmpdir/ref" -xjf "$rs_reference_pkg"

#
# Compare a source archive by extracting both copies into dedicated directories
# and running diff.  Extra arguments (--exclude=...) are forwarded to diff.
#
rs_compare_source_archive()
{
	local name="$1"
	shift
	echo "Comparing $name..."
	mkdir -p "$rs_tmpdir/gen_src/$name" "$rs_tmpdir/ref_src/$name"
	tar --strip-components=1 -C "$rs_tmpdir/gen_src/$name" -xjf "$rs_tmpdir/gen/sources/$name.tar.bz2"
	tar --strip-components=1 -C "$rs_tmpdir/ref_src/$name" -xjf "$rs_tmpdir/ref/sources/$name.tar.bz2"
	diff -ru "$@" "$rs_tmpdir/gen_src/$name" "$rs_tmpdir/ref_src/$name" || rs_failed=1
}

#
# Compare source archives
#
# Per-tool exclusions are documented in AGENTS.md ("Known Differences").
#
echo
echo "=== Comparing source archives ==="
rs_compare_source_archive "binutils" --exclude="*tic80*" --exclude="*cr16c*" --exclude=doc --exclude=testsuite --exclude=emulparams --exclude="elf32*"
rs_compare_source_archive "bison"
rs_compare_source_archive "cmake" --exclude=.gitattributes --exclude=.github --exclude=.gitignore --exclude=.hooks-config --exclude=CMakeVersion.cmake --exclude=Git --exclude=GitSetup --exclude=SetupForDevelopment.sh
rs_compare_source_archive "flex" --exclude=build-aux --exclude=po --exclude=Makefile.in --exclude=configure --exclude=doc --exclude=libtool.m4
rs_compare_source_archive "gcc"
rs_compare_source_archive "gmp"
rs_compare_source_archive "mingw_w64"
rs_compare_source_archive "mpc"
rs_compare_source_archive "mpfr"
rs_compare_source_archive "ninja"

#
# Compare non-source files
#
# README.pdf is excluded because its binary representation varies with the
# tooling used to generate it.  Source archives were compared above.
#
# The following files differ from the 2.2.1 reference due to intentional
# changes made after that release:
#   RosBE-Builder.sh — interactive-only root check; explicit python invocation
#   RosBE-rc         — PATH preservation fix (commit 7ae7c50)
#   cpucount.c       — copyright year update (commit a86ee7e)
#   scut.c           — copyright year update (commit a86ee7e)
#
echo
echo "=== Comparing non-source files ==="
diff -ru \
	--exclude=sources --exclude=README.pdf \
	--exclude=RosBE-Builder.sh --exclude=RosBE-rc \
	--exclude=cpucount.c --exclude=scut.c \
	"$rs_tmpdir/gen" "$rs_tmpdir/ref" || rs_failed=1

echo
if [[ "$rs_failed" -ne 0 ]]; then
	echo "FAIL: Unexpected differences found between packages."
	exit 1
fi
echo "PASS: Packages match within expected tolerances."
