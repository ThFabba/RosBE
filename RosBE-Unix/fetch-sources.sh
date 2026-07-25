#!/usr/bin/env bash
#
# ReactOS Build Environment for Unix-based Operating Systems - Source Archive Fetcher
# Copyright 2024 Colin Finck <colin@reactos.org>
#
# Released under GNU GPL v2 or any later version.
#
# Downloads the pre-built RosBE 2.2.1 source archives from the ReactOS SVN
# mirror into Base-i386/sources/, and generates a README.pdf placeholder so
# that makepackage.sh can run without additional dependencies.
#
# This is an early implementation.  A future revision (see AGENTS.md, Next
# Action 4) will download upstream sources, verify SHA-256 hashes, apply
# patches, run any required build-time preparation, and repack everything from
# scratch.

set -e

#
# Get the absolute path to the script directory
#
# shellcheck disable=SC2006,SC2046
# Reason: follows existing RosBE script convention (see AGENTS.md, Script Design)
cd `dirname "$0"`
rs_scriptdir="$PWD"

#
# Configuration
#
rs_version="2.2.1"
rs_svn_base_url="https://svn.reactos.org/RosBE-Sources/rosbe_${rs_version}"
rs_sources_dir="${rs_scriptdir}/Base-i386/sources"

rs_archives=(
	binutils
	bison
	cmake
	flex
	gcc
	gmp
	mingw_w64
	mpc
	mpfr
	ninja
)

#
# Download source archives
#
echo "Downloading RosBE ${rs_version} source archives..."
mkdir -p "${rs_sources_dir}"

for rs_name in "${rs_archives[@]}"; do
	echo "  ${rs_name}.tar.bz2..."
	if ! curl \
		--retry 3 \
		--retry-delay 10 \
		--max-time 300 \
		--fail \
		--location \
		--output "${rs_sources_dir}/${rs_name}.tar.bz2" \
		"${rs_svn_base_url}/${rs_name}.tar.bz2"; then
		echo "ERROR: Failed to download ${rs_name}.tar.bz2" >&2
		exit 1
	fi
done

#
# Generate README.pdf placeholder
#
# makepackage.sh requires Base-i386/README.pdf to exist.  The authoritative
# source is Base-i386/README.odt; to produce a real PDF, convert it with
# LibreOffice headless.  For CI purposes a minimal placeholder is sufficient
# because makepackage.sh only checks that the file exists.
# compare-packages.sh must exclude README.pdf when comparing against the
# official release.
echo "Creating README.pdf placeholder..."
printf '%%PDF-1.4\n%%%%EOF\n' > "${rs_scriptdir}/Base-i386/README.pdf"

echo "Done."
