Information
------------

This "RosBE-Unix" Git directory tracks the script files for the ReactOS Build
Environment for Unix-based operating systems.

It does not contain a fully functional Build Environment as the source
archives (binutils, GCC, etc.) are not stored in Git.

To create a distributable package:
  1. Run fetch-sources.sh to download and prepare the source archives.
  2. Run makepackage.sh to bundle everything into a distributable tarball.

See AGENTS.md for full documentation on the packaging automation project,
including design decisions, testing workflow, and guidance for contributors
and AI agents working on this code.

You can download a pre-built RosBE-Unix package from
https://sourceforge.net/projects/reactos/files/RosBE-Unix/
