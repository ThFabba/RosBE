# RosBE-Unix Packaging Automation — Agent Guide

This file is for AI agents (and human contributors) working on the packaging
automation project for RosBE-Unix. Read it fully before making any changes.
Update the **Current Status** and **Discussion Log** sections as you work.


## Project Overview

The `RosBE-Unix` directory contains scripts and configurations for the
ReactOS Build Environment (RosBE) targeting Unix-based operating systems.
The repository tracks script files but does **not** include the large upstream
source archives (binutils, GCC, flex, etc.) needed to build the environment.

Distribution packages are built by `makepackage.sh`, which bundles
pre-prepared source archives from `Base-i386/sources/` together with the
scripts into a distributable `.tar.bz2`.

### The Problem

The source archives in `Base-i386/sources/` must currently be prepared
manually — downloaded, patched, and repacked as `.tar.bz2` files with a
specific directory layout.  There is no automation for this step, making it
hard to:

- Reproduce the package-building process
- Validate script changes in CI
- Onboard new contributors


## Goals

Automate the entire packaging pipeline in the following phases:

1. **Fetch & prepare sources** — Download upstream tarballs, verify hashes,
   apply patches, run any required build-time preparation (e.g. flex's
   `autogen.sh` + `make dist`), and repack everything in the layout expected
   by `makepackage.sh`.
   *New script: `fetch-sources.sh`*

2. **Build the distribution package** — Run `makepackage.sh` to produce the
   distributable `.tar.bz2`.
   *Existing script.*

3. **Compare to a reference** — Verify the generated package matches a
   known-good reference (e.g. the official RosBE 2.2.1 release), with
   allowances for known differences.
   *New script: `compare-packages.sh`*

4. **Install the package** — Run `RosBE-Builder.sh` to compile and install
   the toolchain on the host.
   *Existing script.*

5. **Build ReactOS** — Use the installed toolchain to actually build ReactOS.
   *Out of scope for this repository.*

GitHub CI should be able to run any subset of these phases, so developers can
choose the validation depth appropriate for a given PR.


## Current Status

- [x] Repository structure and existing scripts in place
- [x] `makepackage.sh` exists and works
- [x] `RosBE-Builder.sh` exists and works
- [x] Agent guidance documentation (this file)
- [ ] `fetch-sources.sh` — needs to be created (see design notes below)
- [ ] `cmake.patch` — must be located and committed before `fetch-sources.sh`
      can be fully tested (see "Missing Pieces" below)
- [ ] `compare-packages.sh` — needs to be created (see design notes below)
- [ ] GitHub Actions CI workflow — needs to be created


## Script Design

### `fetch-sources.sh`

**Location:** `RosBE-Unix/fetch-sources.sh`

**What it does:**

1. Create a working directory (default: `~/.rosbe-work`) and a log
   subdirectory inside it.
2. Download each upstream source archive using `curl`.
3. Verify SHA-256 hashes with `sha256sum -c`.
4. For each tool, extract the archive, apply any patches, run any required
   build-time preparation, and repack the result as
   `Base-i386/sources/<name>.tar.bz2`.
5. Print a short status line for each step; route verbose output to log files;
   report the log path on failure.

**Why versions/URLs/hashes live in the script itself:**
The preparation steps for each tool are tightly coupled to its version.
Updating a tool almost always requires reviewing and updating the preparation
steps, so a separate config file would give a false sense that bumping a
version variable is sufficient.  Keeping everything in one place makes the
coupling explicit.

**Prototype:**
A working prototype was provided in the problem statement.  Use it as the
reference for logic, but rewrite it to follow the style conventions below.

### `compare-packages.sh`

**Location:** `RosBE-Unix/compare-packages.sh`

**What it does:**

1. Accept a path to a reference package (e.g. the official
   `RosBE-Unix-2.2.1.tar.bz2`).
2. Extract both the generated and reference packages to temporary directories.
3. Compare source archives and/or the full directory tree with `diff`.
4. Apply the exclusions documented in "Known Differences" below so that
   tolerated discrepancies do not cause false failures.
5. Produce a clear pass/fail result with details on any unexpected differences.

### Missing Pieces

**`cmake.patch`:** The prototype references `$SCRIPT_DIR/cmake.patch` but
this file is not yet in the repository.  The CMake source used is the ReactOS
fork (`reactos/CMake`, branch `cmake-3.17.2-reactos`, commit `07c58033`).
The patch captures changes made on top of upstream CMake 3.17.2 that are not
captured in that fork's commit history (i.e. local working-tree changes that
were manually applied before packaging).

To resolve this, an agent should:
1. Inspect the ReactOS CMake fork at the relevant commit.
2. Diff it against a clean upstream CMake 3.17.2 tree to identify any
   additional working-tree changes that belong in a patch.
3. Commit the resulting patch to `RosBE-Unix/cmake.patch` (keeping it next
   to the script that uses it, consistent with the prototype's `$SCRIPT_DIR`
   reference).


## Source Versions and Hashes

All version numbers, URLs, and expected SHA-256 hashes go inside
`fetch-sources.sh`.  For reference, the values used in the RosBE 2.2.1
release are:

| Tool       | Version / Revision | Source                                                       |
|------------|--------------------|--------------------------------------------------------------|
| Binutils   | 2.34               | https://ftp.gnu.org/gnu/binutils/                            |
| Bison      | 3.5.4              | https://ftp.gnu.org/gnu/bison/                               |
| CMake      | 3.17.2 (07c58033)  | https://github.com/reactos/CMake (branch cmake-3.17.2-reactos) |
| Flex       | 2.6.4+ (8b1fbf67)  | https://github.com/westes/flex (git archive)                 |
| GCC        | 8.4.0              | https://ftp.gnu.org/gnu/gcc/                                 |
| GMP        | 6.2.0              | https://ftp.gnu.org/gnu/gmp/                                 |
| mingw-w64  | 6.0.0              | https://sourceforge.net/projects/mingw-w64/                  |
| MPC        | 1.1.0              | https://ftp.gnu.org/gnu/mpc/                                 |
| MPFR       | 4.0.2              | https://www.mpfr.org/                                        |
| Ninja      | 1.10.0             | https://github.com/ninja-build/ninja                         |

Patches are stored in `Patches/` at the repository root.  The patches used
for RosBE 2.2.1 are:

- `bison-3.5-reactos-fix-win32-build.patch`
- `GMP-6.2.0-C89-fixes.patch`
- `cmake.patch` (to be committed — see "Missing Pieces" above)

SHA-256 hashes for the downloaded archives (from the prototype):

```
f00b0e8803dc9bab1e2165bd568528135be734df3fabf8d0161828cd56028952  binutils-2.34.tar.xz
c0dd154dfaba63553a892d41dc400c7baa88cc06a1e2e27813fdd503715e4c28  bison-3.5.4.tar.gz
e30a6e52d10e1f27ed55104ad233c30bd1e99cfb5ff98ab022dc941edd1b2dd4  gcc-8.4.0.tar.xz
258e6cd51b3fbdfc185c716d55f82c08aff57df0c6fbd143cf6ed561267a1526  gmp-6.2.0.tar.xz
805e11101e26d7897fce7d49cbb140d7bac15f3e085a91e0001e80b2adaf48f0  mingw-w64-v6.0.0.tar.bz2
6985c538143c1208dcb1ac42cedad6ff52e267b47e5f970183a3e75125b43c2e  mpc-1.1.0.tar.gz
1d3be708604eae0e42d578ba93b390c2a145f17743a744d8f3f8c2ad5855a38a  mpfr-4.0.2.tar.xz
3810318b08489435f8efc19c05525e80a993af5a55baa0dfeae0465a9d45f99f  ninja-1.10.0.tar.gz
243e3d48b1af2bc9db9acab709f702031f15f39124720c2d3dae2d16b73074fb  cmake-3.17.2-07c58033.zip
1455ecf338ad889e8003aa0dc255f883a3f5c2e97a2ac0bedd9034d333ec6c07  flex-2.6.4-8b1fbf67.zip
1dc81140c60cc69056a5a4bbfe61a874db8ae5cd9f89df72f80f114dfecb9802  bison-3.5-reactos-fix-win32-build.patch
83652d4cd41efa860dcd7557994c8b9c18e2cc7ba0476dcffd46fa09197fbaf2  GMP-6.2.0-C89-fixes.patch
```


## Known Differences Between Automated and Manual RosBE 2.2.1

The official RosBE 2.2.1 distribution package was not built using automation.
`compare-packages.sh` must tolerate these known discrepancies when comparing
against that release.  Once an official release is built using automation,
these allowances should be tightened.

| Tool      | Expected differences / exclusions                                        |
|-----------|--------------------------------------------------------------------------|
| Flex      | `build-aux`, `po`, `Makefile.in`, `configure`, `doc`, `libtool.m4`       |
| CMake     | `.gitattributes`, `.github`, `.gitignore`, `.hooks-config`,              |
|           | `CMakeVersion.cmake`, `Git`, `GitSetup`, `SetupForDevelopment.sh`        |
| Binutils  | Files matching `*tic80*`, `*cr16c*`; directories `doc`, `testsuite`,     |
|           | `emulparams`; files matching `elf32*`                                    |
| All tools | The outer `.tar.bz2` compression may differ; compare extracted contents  |

All other tools (Bison, GCC, mingw-w64, GMP, MPC, MPFR, Ninja) should match
the reference exactly once `cmake.patch` is sorted out.


## Shell Script Style Conventions

Study the existing scripts — `RosBE-Builder.sh`, `makepackage.sh`,
`scripts/setuplibrary.sh` — for style.  New scripts must follow these rules:

### General

- **Shebang:** `#!/usr/bin/env bash`
- **License header:** Copyright block with author(s) and
  "Released under GNU GPL v2 or any later version."
- **Indentation:** Tabs (not spaces).
- **Line length:** No hard limit, but keep lines readable.
- **Sections:** Use `###...###` comment blocks (matching the width in
  existing scripts) to delimit major sections.

### Variables

- `UPPER_CASE` for script-level constants and configuration (versions, paths,
  filenames, hashes).
- `lower_case` for local variables inside functions.
- Always double-quote variable expansions: `"$VAR"`, `"${VAR}"`.

### Conditionals and tests

- Use `[[ ]]` (bashism) rather than `[ ]` — consistent with existing scripts.
- Use `if`/`elif`/`else`/`fi` blocks; avoid single-line `&&` chains for
  anything beyond trivial guard clauses.

### Error handling

- **Use `set -e`** at the top of new scripts.  This is a modern best practice
  that makes failures fail-fast.  The existing scripts check `$?` manually,
  but new scripts should prefer `set -e` for safety.  *(This was discussed
  with the project owner and agreed upon.)*
- For commands where failure needs a custom message or log reference, use:
  ```bash
  some_command > "$LOG_DIR/step.log" 2>&1 \
      || { echo "Step failed. See $LOG_DIR/step.log"; exit 1; }
  ```
- Always include the log path in error messages.

### Paths and `cd`

- Determine the script's own directory with:
  ```bash
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
  ```
- Avoid bare `cd` without error handling; under `set -e` a failed `cd` will
  abort the script, which is the desired behaviour.

### Logging

- Route verbose/build output to a log file.
- Print a short, human-readable status line to stdout for each major step
  (e.g. `echo "Preparing bison..."`).
- On failure, print the log path so the user can investigate.

### Shellcheck

- New scripts must pass `shellcheck` without warnings, or document any
  suppressed warnings with an inline comment explaining why.


## Testing Workflow

Agents **must** follow this workflow before declaring any task complete:

1. **Syntax check:**
   ```bash
   bash -n RosBE-Unix/fetch-sources.sh
   bash -n RosBE-Unix/compare-packages.sh
   ```

2. **Shellcheck:**
   ```bash
   shellcheck RosBE-Unix/fetch-sources.sh
   shellcheck RosBE-Unix/compare-packages.sh
   ```
   Address all warnings, or add an inline suppression comment with a
   justification.

3. **Integration test — `fetch-sources.sh`:**
   Run the script on a Linux host that has `autoconf`, `automake`, `libtool`,
   `gettext`, `flex` (host), `bison` (host), and standard build tools
   installed.  Verify that:
   - All downloads complete and hashes pass.
   - All `Base-i386/sources/*.tar.bz2` files are created.
   - Each archive extracts to a directory with the expected name.

4. **Integration test — `compare-packages.sh`:**
   Download the official `RosBE-Unix-2.2.1.tar.bz2` release and run:
   ```bash
   RosBE-Unix/compare-packages.sh /path/to/RosBE-Unix-2.2.1.tar.bz2
   ```
   The script must exit 0 and report no unexpected differences.

5. **CI:** Once the GitHub Actions workflow exists, ensure it passes.

If an integration test cannot be run in your environment (e.g. no internet
access or missing build tools), state this explicitly in your PR description
and confirm that at least steps 1 and 2 pass.


## Discussion Log

Record significant design decisions and their rationale here so future agents
have context.  Add new entries at the top.

---

**2026-07 — Initial setup (add-guidance-files branch)**

- Established this guide based on the problem statement and prototype script
  provided by the project owner.
- Decided: version/URL/hash data stays in `fetch-sources.sh` (not a separate
  config) because preparation steps are version-coupled.
- Decided: `set -e` will be used in new scripts, departing from the existing
  manual `$?` style, because it is safer and the project owner agreed.
- Identified gap: `cmake.patch` is referenced by the prototype but not yet
  in the repository.  A future agent must locate and commit it.
- Identified gap: GitHub Actions CI workflow does not yet exist.
- Known differences table populated from the prototype's comparison
  exclusions; these should be tightened once the first automated release is
  made.
