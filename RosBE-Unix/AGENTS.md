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

**Long-term platform goal:** Fix RosBE-Unix support on macOS running Apple Silicon
(M-series).  GitHub provides `macos-14` and `macos-15` hosted runners, both of
which are native arm64 (`macos-latest` resolves to `macos-15` as of mid-2026).
Adding CI coverage for macOS on Apple Silicon is a future goal; do not attempt
it until the Linux pipeline is stable and the required porting work is done.


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
- [x] `cmake.patch` — committed to `RosBE-Unix/cmake.patch`
- [ ] `compare-packages.sh` — needs to be created (see design notes below)
- [x] GitHub Actions CI workflow — `.github/workflows/rosbe-unix-validate.yml` (Next Action 1)


## Next Actions

The items below are concrete sequential tasks.  Complete each before starting
the next, unless there is a blocking external constraint.  See also the
"Fork and Upstream Strategy" section for ongoing principles that apply
throughout all work.

1. **Validate the existing RosBE-Unix 2.2.1 release end-to-end.**
   Download the published `RosBE-Unix-2.2.1.tar.bz2`, install it via
   `RosBE-Builder.sh`, and use the resulting toolchain to build ReactOS.
   This confirms the current release still works in the CI environment and
   surfaces any host-environment issues before we start changing anything.
   Add a CI job for this step.

2. **Validate `makepackage.sh` using pre-built source archives.**
   Download the source archives from `https://svn.reactos.org/RosBE-Sources/rosbe_2.2.1/`
   (as documented in `Git-Readme.txt`), run `makepackage.sh`, and verify the
   output can be installed and used to build ReactOS.
   Add a CI job for this step.

3. **Write and validate `compare-packages.sh`.**
   Implement the script (see Script Design section), use it to compare the
   package built in step 2 against the public 2.2.1 release, and add
   a CI job that runs this comparison.  This connects the two existing
   processes and gives us a reproducibility baseline.

4. **Write and validate `fetch-sources.sh`.**
   Implement the script (see Script Design section).  Replace the manual SVN
   source download in step 2 with `fetch-sources.sh`, confirm the output of
   `makepackage.sh` still passes `compare-packages.sh`, and add or update the
   CI job accordingly.  Add static checks (`bash -n`, `shellcheck`) for both
   new scripts as part of the PRs that introduce them.


## Script Design

### `fetch-sources.sh`

**Location:** `RosBE-Unix/fetch-sources.sh`

**What it does:**

1. Create a working directory without assuming `~/.rosbe-work` is appropriate.
   Prefer behavior consistent with the existing RosBE scripts: work from inside
   the repository checkout when practical, ensure each run starts from a clean
   tree, and make any alternate work directory configurable.
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
reference for **logic**, but **do not copy its style** — the prototype
intentionally did not follow RosBE conventions.  Rewrite it using the style
conventions documented below.

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

### `cmake.patch`

**Location:** `RosBE-Unix/cmake.patch`

This patch fixes a compilation error that occurs when building CMake on modern
Linux with GCC 16.  It wraps a `#include "cmGlobalGhsMultiGenerator.h"` in an
`#ifndef CMAKE_BOOTSTRAP` guard inside `Source/cmake.cxx`.

**Important:** this patch was **not** applied when the official RosBE 2.2.1
release was packaged, so `compare-packages.sh` must **not** factor it in —
the comparison should use the unpatched CMake source.  However, the patch
**will** be needed during phase 4 (installing the package / running
`RosBE-Builder.sh`) on modern distros.  Apply it after `fetch-sources.sh`
produces the CMake source archive and before running `RosBE-Builder.sh`, or
handle it conditionally in a future iteration.

The patch content is in `RosBE-Unix/cmake.patch`.  In brief, it wraps a
`#include "cmGlobalGhsMultiGenerator.h"` in an `#ifndef CMAKE_BOOTSTRAP`
guard inside `Source/cmake.cxx`.  The fetch script references it as
`$rs_scriptdir/cmake.patch`, consistent with how `RosBE-Builder.sh` locates
files relative to its own directory.


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

`cmake.patch` (at `RosBE-Unix/cmake.patch`) is also used by `fetch-sources.sh`
but was **not** part of the 2.2.1 release package — see the `cmake.patch`
section under Script Design.

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

**Note on cmake.patch:** `cmake.patch` was NOT applied when building the
2.2.1 release, so the comparison must use the unpatched CMake tree (i.e. do
not apply `cmake.patch` before running `compare-packages.sh`).

**Note on flex:** The exact file set produced by flex's `autogen.sh` +
`make dist` depends on the host versions of `autoconf`, `automake`,
`libtool`, `bison`, `help2man`, and `texinfo`.  The 2.2.1 release was
prepared with these specific versions:

- autoconf 2.69
- automake 1.15.1
- bison 3.0.4
- help2man 1.47.6
- libtool 2.4.6
- texinfo 6.5

Using different versions will produce a larger diff in the flex source.  CI
and testing environments should either install the exact versions above to
minimise the diff, or accept the larger diff by adding more flex exclusions.

To reduce the remaining diff further, investigate whether the historical RosBE
package was prepared with Debian-patched autotools and whether generated
documentation timestamps can be normalised during preparation.

All other tools (Bison, GCC, mingw-w64, GMP, MPC, MPFR, Ninja) should match
the reference exactly.

**Note on CMake:** Some remaining differences appear to come from using
`git archive`.  If closer reproduction is needed, prefer a clean `git clone`
and `checkout` workflow over archive snapshots when preparing the CMake source.

**Note on binutils:** Some remaining differences appear to come from extracting
new content over an old tree and from downstream distro patching.  Always
prepare binutils from a clean extraction, and compare against Debian patchsets
if exact historical reproduction becomes necessary.


## Shell Script Style Conventions

Study the existing scripts — `RosBE-Builder.sh`, `makepackage.sh`,
`scripts/setuplibrary.sh` — for style.  The prototype script provided in the
problem statement intentionally did **not** follow RosBE conventions; new
scripts must.

### General

- **Shebang:** `#!/usr/bin/env bash`
- **License header:** Copyright block with author(s) and
  "Released under GNU GPL v2 or any later version."
- **Indentation:** Tabs (not spaces).
- **Line length:** No hard limit, but keep lines readable.
- **Section comments:** Use the `#` / `# Section name` / `#` three-line
  style seen in `makepackage.sh` and `RosBE-Builder.sh`, for example:
  ```bash
  #
  # Download sources
  #
  ```
  Do **not** use `###...###` banner-style blocks — those are not a RosBE
  convention.
- **Script naming:** Lowercase with hyphens where needed, matching
  `makepackage.sh` and `makepackage-deb.sh`.  The new scripts are
  `fetch-sources.sh` and `compare-packages.sh`.

### Variables

- **Use the `rs_` prefix** and lowercase for all script-level variables,
  following the convention in `setuplibrary.sh` and `RosBE-Builder.sh`
  (e.g. `rs_scriptdir`, `rs_workdir`, `rs_bison_version`).
- Local variables inside functions may omit the prefix and use `local`.
- Always double-quote variable expansions: `"$rs_var"`, `"${rs_var}"`.
  This is a correctness requirement for paths containing spaces, not merely a
  style preference.  Future validation should include at least one path-with-
  spaces scenario where practical.

### Error handling

- **Use `set -e`** at the top of new scripts.  This is a modern best practice
  that makes failures fail-fast.  The existing scripts check `$?` manually,
  but new scripts should prefer `set -e` for safety (discussed with the
  project owner; agreed to keep).
- Use `rs_do_command` from `setuplibrary.sh` to run build commands.  It writes
  command output to `$rs_workdir/build.log`, prints a short status line, and
  calls `rs_check_run` which exits with a clear message on failure.  The log
  path is reused across commands and deleted on success by the current helper
  implementation.  This replaces the prototype's per-step
  `{ echo "step failed. See log"; exit 1; }` pattern.
- For steps that `rs_do_command` cannot wrap (e.g. `patch`, `unzip`), redirect
  output to `$rs_workdir/build.log` and let `set -e` handle failure, or use:
  ```bash
  some_command >> "$rs_workdir/build.log" 2>&1
  ```

### Logging

- Use the `setuplibrary.sh` log path `$rs_workdir/build.log` rather than
  per-step log files, unless there is a strong reason to diverge.
- Print a short, human-readable status line to stdout for each major step
  (e.g. `echo "Preparing bison..."`).

### Script directory

- Determine the script's own directory using the RosBE pattern:
  ```bash
  cd `dirname $0`
  rs_scriptdir="$PWD"
  ```
  Do **not** use the `BASH_SOURCE`-based pattern from the prototype —
  that was not part of the existing RosBE style.

### Conditionals and tests

- Prefer `[[ ]]` in new bash scripts.  Existing RosBE scripts currently mix
  `[[ ]]` and `[ ]`, so match the surrounding style when touching older code.
- Use `if`/`elif`/`else`/`fi` blocks; avoid single-line `&&` chains for
  anything beyond trivial guard clauses.

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
   Run the script on a Linux host with standard build tools installed.
   For the flex source to match the RosBE 2.2.1 reference as closely as
   possible, install these specific versions of the host tools that flex's
   `autogen.sh` + `make dist` invokes (see "Known Differences" above):
   - autoconf 2.69, automake 1.15.1, libtool 2.4.6
   - bison 3.0.4, help2man 1.47.6, texinfo 6.5
   Also install Python 3.12.x — Ninja 1.10.0's bootstrap (`configure.py`)
   requires a Python version that understands the script; Python 3.12.13
   is known to work.
   Verify that:
   - All downloads complete and hashes pass.
   - All `Base-i386/sources/*.tar.bz2` files are created.
   - Each archive extracts to a directory with the expected name.

4. **Integration test — `compare-packages.sh`:**
   Download the official `RosBE-Unix-2.2.1.tar.bz2` release and run:
   ```bash
   RosBE-Unix/compare-packages.sh /path/to/RosBE-Unix-2.2.1.tar.bz2
   ```
   The script must exit 0 and report no unexpected differences.
   Remember: do **not** apply `cmake.patch` to the sources before this
   comparison (see "Known Differences").

5. **CI:** Each PR that introduces a script or workflow change must pass the
   relevant CI jobs.  New scripts must also pass `bash -n` and `shellcheck`
   as part of the PR that introduces them.

### CI jobs and their order

Each CI job below corresponds to a step in the "Next Actions" roadmap and
should be added in that order, because each one builds on the confidence
established by the previous.

1. **Install the published release (`Next Action 1`)** — Download
   `RosBE-Unix-2.2.1.tar.bz2`, install it via `RosBE-Builder.sh`, and
   verify with a cross-compile smoke test.  This is the first CI job added and
   validates the current release in our hosted environment before any code is
   changed.  A separate manual-trigger-only workflow (`rosbe-unix-build-reactos.yml`)
   then installs the toolchain again from scratch and builds the `bootcd` target.
   The shared install steps live in the composite action at
   `.github/actions/install-rosbe/action.yml` to avoid duplication.

2. **Repackage from pre-built archives (`Next Action 2`)** — Download the
   pre-built source archives from
   `https://svn.reactos.org/RosBE-Sources/rosbe_2.2.1/`, run `makepackage.sh`,
   install the resulting package, and repeat the ReactOS build.  This validates
   that the repository's existing packaging scripts still work independently of
   the published binary.

3. **Compare packages (`Next Action 3`)** — Run `compare-packages.sh` on the
   package built in job 2 against the published `RosBE-Unix-2.2.1.tar.bz2`.
   Added when `compare-packages.sh` is written.

4. **Full fetch-then-build pipeline (`Next Action 4`)** — Run
   `fetch-sources.sh`, then `makepackage.sh`, then `compare-packages.sh`, then
   `RosBE-Builder.sh`, then the ReactOS build.  Added when `fetch-sources.sh`
   is written.

Adding CI jobs in this order provides the clearest regression story for
upstream reviewers: first prove the current release works in CI, then prove the
repository can reproduce it, then replace manual steps with automation.

If an integration test cannot be run in your environment (e.g. no internet
access or missing build tools), state this explicitly in your PR description
and confirm that at least `bash -n` and `shellcheck` pass for any new scripts.


## Fork and Upstream Strategy

Development happens in this fork, but the eventual submission target is the
upstream RosBE repository.

- `AGENTS.md` is fork-only process documentation and must **not** be proposed
  for upstream.
- Prefer to finish development and validation in this fork before preparing the
  upstream PR series.
- While developing here, keep an explicit upstream plan: separate fork-only
  workflow/docs changes from code that should later be proposed upstream.
- Upstream-facing PRs should emphasise regression coverage and testing results,
  especially for existing functionality such as `makepackage.sh`,
  `RosBE-Builder.sh`, and the published RosBE 2.2.1 package/install flow.


## Discussion Log

Record significant design decisions and their rationale here so future agents
have context.  Add new entries at the top.

---

**2026-07 — Refactor to composite action + two independent workflows
(download-rosbe-installer-and-setup branch)**

Observed that GitHub Actions does not allow a skipped job to be resumed later
in the same run.  The artifact-based two-job design (upload toolchain in job 1,
download in job 2 when `run_reactos_build=true`) therefore provides no
practical value: triggering a ReactOS build always requires starting a fresh
workflow run that re-installs the toolchain regardless.

Refactored to two fully independent workflows, with shared steps extracted into
a local composite action to avoid duplication:

- **`.github/actions/install-rosbe/action.yml`** — composite action containing
  all install and smoke-test steps (apt dependencies, tarball download,
  extraction, `RosBE-Builder.sh`, verify, cross-compile check).  The caller
  passes the install directory as the `install_dir` input.  Both workflows
  require an `actions/checkout` step first so the local action is available on
  disk.

- **`rosbe-unix-validate.yml`** — triggers on push/PR; single `install-rosbe`
  job; no artifact; calls the composite action.  This is the routine fast CI
  path (~60–90 min).

- **`rosbe-unix-build-reactos.yml`** — `workflow_dispatch` only; single
  `build-reactos` job; calls the composite action then checks out ReactOS and
  builds `bootcd`.  This is the slow full-validation path (~2–3 hours total).

The artifact upload/download and the "Restore executable permissions" workaround
are removed: since both workflows always install fresh, there is no artifact to
download and no need to repair permissions.

---

**2026-07 — CI style, paths-with-spaces finding, and macOS future goal
(download-rosbe-installer-and-setup branch)**

Three topics discussed with the project owner after the Next Action 1 workflow
was working:

**CI YAML style — inline steps vs. extracted shell scripts:**
The community consensus for GitHub Actions is more nuanced than for Bamboo or
Jenkins.  Inline `run:` steps are appropriate when the logic is pure orchestration
(download, extract, call an external script, check a file) and the real business
logic lives in a proper shell script already checked into the repo — as is the
case here (`RosBE-Builder.sh` does the heavy lifting; the workflow steps are
glue).  Extract to a standalone shell script when: (a) the `run:` block is long
and has real branching, (b) the same logic is needed in more than one workflow
file, or (c) the logic needs to be unit-tested independently.  Use a *composite
action* (`.github/actions/my-action/action.yml`) when you need to share a
sequence of named steps across multiple workflow files and want those steps
visible individually in the Actions UI.  **The current workflow is fine as-is.**

**Paths with spaces — existing scripts are not safe:**
Investigated whether the CI setup should test install paths containing spaces.
Conclusion: the existing RosBE-Unix scripts are not safe with paths containing
spaces and CI should not test that scenario yet.

- `scripts/setuplibrary.sh` explicitly aborts if the script directory contains
  a space: it checks for a space in `$rs_scriptdir` early on and exits with an
  error message.
- `RosBE-Builder.sh` still has some unquoted variable expansions (e.g. the
  `ln -s ... $rs_archprefixdir/...` lines), so install paths with spaces are
  not reliably safe.

Treat path-with-spaces support as a **future hardening task**: fix the scripts
first, then add a CI matrix entry that exercises a spaced install path.  The
style convention in this file (always double-quote variable expansions) is
already documenting the right practice for new scripts.

**macOS Apple Silicon — long-term future goal:**
A long-term goal is to fix RosBE-Unix support on macOS running Apple Silicon
and add CI validation for that platform.  GitHub provides `macos-14` and
`macos-15` hosted runners that are native arm64 (`macos-latest` resolves to
`macos-15` as of mid-2026).  Do not pursue this until the Linux pipeline is
stable and the required porting work has been identified.

---

**2026-07 — CI environment investigation and Next Action 1 workflow
(download-rosbe-installer-and-setup branch)**

Investigated the GitHub Actions runner environment and designed the first CI
job (`Next Action 1`).  Key findings:

- **Runner OS:** Ubuntu 24.04 LTS (`ubuntu-latest` as of July 2026).
- **vCPUs:** 4.
- **RAM:** ~16 GB.
- **Disk:** ~80 GB free on the workspace mount — sufficient for the toolchain
  build and the ReactOS source checkout + build artifacts.
- **GCC version on ubuntu-latest:** 13.3.0.  `cmake.patch` (which fixes a
  compilation error in CMake's bootstrap on GCC 16+) is therefore NOT applied
  in this workflow.  If the runner is ever upgraded to a distro that defaults
  to GCC 16+, a patch step must be added before running `RosBE-Builder.sh`.
- **Internet access:** GitHub Actions runners have full internet access.
  SourceForge, `ftp.gnu.org`, and `svn.reactos.org` are all reachable.
  (In the agent sandbox used during development, only `github.com` was
  accessible; all other hosts were blocked by the DNS monitoring proxy.  This
  is a sandbox limitation, not a GitHub Actions limitation.)

Decided on two-job workflow structure:

1. **`install-rosbe` (runs on every push/PR):** Downloads
   `RosBE-Unix-2.2.1.tar.bz2` from SourceForge, installs it via
   `RosBE-Builder.sh` with a non-interactive install directory argument,
   then verifies the toolchain with a cross-compile smoke test (compiling a
   trivial `int main(void) { return 0; }` to a PE/COFF executable).
   Timeout: 120 minutes (toolchain build typically takes 60–90 min on 4
   vCPUs; 120 min gives headroom without masking genuine hangs).

2. **`build-reactos` (manual `workflow_dispatch` only):** Repeats the
   toolchain installation, then performs a shallow clone of
   `reactos/reactos`, runs CMake to configure the build, and builds the
   `bootcd` target with Ninja.  Estimated additional wall time: 60–120
   minutes.  Total end-to-end time: roughly 2–3 hours.

Constraint documented: a full ReactOS build is feasible within the 6-hour
GitHub Actions job limit (total ~2–3 hours), but is too expensive to run on
every push or pull request.  The reduced smoke test (cross-compile hello.c
with the installed cross-compiler) still exercises RosBE-Builder.sh
installation end-to-end and is appropriate for routine PR validation.

The `build-reactos` job uses the ReactOS CMake toolchain file at
`sdk/cmake/toolchain-gcc.cmake` and the `bootcd` build target.  The exact
incantation may need adjustment if the ReactOS build system changes; treat it
as a starting point and update when running the job for the first time.

---

**2026-07 — CI ordering and upstream-planning updates (update-readme branch)**

- Clarified that `fetch-sources.sh` must not assume `~/.rosbe-work`; new work
  should stay consistent with the existing in-repo RosBE workflow unless there
  is a strong reason to diverge.
- Rewrote "Next Actions" as a concrete sequential task list; moved ongoing
  principles (CI expansion, upstream plan) to separate sections.
- Adopted a "backwards first" CI rollout: first validate the published 2.2.1
  package end-to-end (install + ReactOS build), then the existing packaging
  scripts, then add compare-packages.sh, then add fetch-sources.sh.  Static
  checks for new scripts are added in the same PR that introduces them, not as
  a prior phase.
- Recorded additional reproducibility notes: flex diffs may require Debian-
  patched host tools and timestamp normalisation; CMake may need `git clone`
  rather than `git archive`; binutils must be prepared from a clean tree.
- Clarified that double-quoting is required for path correctness, not just
  style.
- Documented that `AGENTS.md` is fork-only guidance and should not go upstream;
  development in this fork should still maintain an explicit upstream PR plan.

---

**2026-07 — Style and cmake.patch corrections (update-readme branch)**

- Project owner confirmed: the prototype does NOT follow RosBE style; new
  scripts must.
- Corrected variable naming: use `rs_` lowercase prefix (e.g. `rs_workdir`,
  `rs_bison_version`), not the UPPER_CASE used in the prototype.
- Corrected section comment style: use `#` / `# Name` / `#` three-line
  blocks, not `### ... ###` banners (those were an invention of the prototype).
- Corrected error handling: use `rs_do_command` from `setuplibrary.sh` for
  build steps rather than `{ echo "failed"; exit 1; }` guards.
- Corrected logging: use a single `$rs_workdir/build.log` file, not
  per-step files.
- Corrected script-dir detection: use `cd \`dirname $0\` && rs_scriptdir="$PWD"`,
  not the `BASH_SOURCE`-based pattern.
- `set -e` confirmed: project owner agreed it is a worthwhile modern practice;
  keep it even though existing scripts do not use it.
- `cmake.patch` clarified: the patch content was provided.  It fixes a GCC 16
  build error in `Source/cmake.cxx`.  It was NOT applied for the 2.2.1
  release, so comparison must use the unpatched source.  It IS needed for
  phase 4 (installation) on modern distros.  Commit it as
  `RosBE-Unix/cmake.patch`.
- Flex toolchain versions documented: the 2.2.1 release was prepared with
  autoconf 2.69, automake 1.15.1, bison 3.0.4, help2man 1.47.6,
  libtool 2.4.6, texinfo 6.5.  Using other versions produces a larger diff.
- Python version documented: Python 3.12.13 is known to work with Ninja
  1.10.0's `configure.py` bootstrap.

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
