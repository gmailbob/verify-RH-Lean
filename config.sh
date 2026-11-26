# shellcheck shell=bash
# Pinned inputs for the verification. Every script reads this file, so these
# values are the only place where trust is anchored. Review them before running.
#
# Override any value from the environment, e.g.  WORKDIR=/data/grh JOBS=16 scripts/05-build.sh

# ---------------------------------------------------------------- where to work
# Everything downloaded or produced goes under WORKDIR. Keep it outside this repository.
WORKDIR="${WORKDIR:-$HOME/grh-verify}"

# Parallel build jobs.
JOBS="${JOBS:-$(( $(nproc) > 4 ? $(nproc) - 4 : 1 ))}"

# ---------------------------------------------------------------- the claim
# The shorter Lean proof of RH and of GRH for Dirichlet L-functions published at
# https://github.com/lsernau/grh-lean, readable edition (folder grh/).
SOURCE_REPO_URL="https://github.com/lsernau/grh-lean"
SOURCE_COMMIT="72fead102f663d5c7a407964a13dc0cf9d977207"   # main on 2026-11-25
SOURCE_SUBDIR="grh"                                        # the Lake project inside the repository
# sha256 of the list "<sha256>  ./<path>" of every file under grh/ at that commit, sorted by path
# (what scripts/tools/hash-tree.sh prints). It pins the content independently of git's SHA-1.
SOURCE_TREE_SHA256="ab5bc5e431464ed94f4073ba8b4215481208465d341f702397d81a10b03c25f6"
EXPECTED_FILES=818                     # files under grh/
EXPECTED_SRC_LEAN_FILES=803            # .lean files under grh/src
EXPECTED_LEAN_FILES=805                # all .lean files under grh/: those, Challenge.lean and
                                       # scripts/PrintAxioms.lean, which the build does not use

# ---------------------------------------------------------------- toolchain
LEAN_VERSION="4.35.0"
LEAN_COMMIT="eb6cafb7290e8bd5f2937522d8d804f58f02bafc"   # git tag v4.35.0 in leanprover/lean4
LEAN_RELEASE_URL="https://github.com/leanprover/lean4/releases/download/v${LEAN_VERSION}"
# sha256 of the official release assets (cross-checked against the GitHub API digest).
LEAN_SHA256_x86_64="7289597a44543246c9227b8cae501767e095ce17f6d448b95fc4a8dc97268f6d"
LEAN_SHA256_aarch64="c8f0f8a3920e839718b1343e6781fd80a3e9b1024fbcd7078eb30f54e806b028"

# ---------------------------------------------------------------- dependencies
# Expected lake-manifest.json revisions live in expected/lake-manifest.revs
MATHLIB_REV="56a005855ea17e0b0958f73ec801ae140b0a1679"

# ---------------------------------------------------------------- machine minimums
# Measured in our run: 23 GB in WORKDIR at the end (toolchain 3 GB; Mathlib, the other packages
# and the project's build 15 GB; the step 9 export 4.5 GB; the rest is logs and optional tools).
MIN_FREE_DISK_GB=30
REC_FREE_DISK_GB=50
MIN_MEM_PLUS_SWAP_GB=24      # RAM + swap. Upstream: "one to two hours on 12 cores with 24 GB"
MEM_PER_JOB_GB=1             # warn below this much RAM per build job. Measured: 22.7 GiB in use
                             # at the peak of a 28-job build, about 0.8 GiB per job.
MIN_FREE_INODES=1000000
MIN_OPEN_FILES=4096
# vm.max_map_count: Lean maps every imported module in up to three mappings. Measured in our
# run: a Lean process that imports the whole project (11,779 modules with Mathlib and Lean's own
# library) holds 55,794 mappings, and the largest count seen during the build was 55,767. That is
# 85% of the Linux default of 65,530, so the default is enough by this measurement. Our machine
# was set higher, so we did not run at the default itself.
MIN_MAX_MAP_COUNT=65530      # the Linux default

# ---------------------------------------------------------------- step 9: independent kernels
# The exporter (leanexport) and the checkers (con-leche, con-ron, nanoda_bin) are the binaries
# shipped in the Lean release pinned above, so step 9 needs no further downloads or pins.
# expected/export-targets.txt: the declarations to export (the five final theorems; everything
# they depend on is exported with them).
EXPORT_TARGETS_SHA256="29b58ec2d53fb574008278e66ef12c470407a1244e2225140215005263abbe6a"
