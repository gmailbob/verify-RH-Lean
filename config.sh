# shellcheck shell=bash
# Pinned inputs for the verification. Every script reads this file, so these
# values are the only place where trust is anchored. Review them before running.
#
# Override any value from the environment, e.g.  WORKDIR=/data/rh JOBS=16 scripts/05-build.sh

# ---------------------------------------------------------------- where to work
# Everything downloaded or produced goes under WORKDIR (about 1.2 TB at the end).
# Keep it outside this repository.
WORKDIR="${WORKDIR:-$HOME/rh-verify}"

# Parallel build jobs. Each Lean process needs ~1 GB RAM on average, more at peaks.
JOBS="${JOBS:-$(( $(nproc) > 4 ? $(nproc) - 4 : 1 ))}"

# ---------------------------------------------------------------- the claim
SOURCE_BASE_URL="https://alpo.ge"
ANNOUNCEMENT_FILE="remark.pdf"
ANNOUNCEMENT_SHA256="3fc97784b71ddd44ff8aa0a177e99622a1c61b13cfa843a0989ee4a7a0cfeb8d"
ANNOUNCEMENT_SIZE=245114

ARCHIVE_NAME="lean.tar.gz"
ARCHIVE_PARTS=14                       # lean.tar.gz.part01 .. part14
ARCHIVE_SHA256="9631b4f020199e580ba86178cb56c6e9b09f690c2369a80dc4334aa93f49c7fc"
ARCHIVE_SIZE=239275554
# Per-part hashes live in expected/archive-parts.sha256

# What the archive must contain once extracted.
EXPECTED_FILES=175190                  # regular files (175,187 .lean + lakefile, manifest, toolchain file)
EXPECTED_LEAN_FILES=175187
EXPECTED_ROOT_DIR="lean"

# ---------------------------------------------------------------- toolchain
LEAN_VERSION="4.33.1"
LEAN_COMMIT="819816b2e0a3bf405af45ae5c7af2491d8f5bee6"   # git tag v4.33.1 in leanprover/lean4
LEAN_RELEASE_URL="https://github.com/leanprover/lean4/releases/download/v${LEAN_VERSION}"
# sha256 of the official release assets (cross-checked against the GitHub API digest).
LEAN_SHA256_x86_64="890afd185370f85666025b883914ab4f4b339136f8c96167b69cfb62aecaf235"
LEAN_SHA256_aarch64="f7353a8b2a8741c84558523e450556f9a1c45e3cafcf54399ce68c6a24c55f07"

# ---------------------------------------------------------------- dependencies
# Expected lake-manifest.json revisions live in expected/lake-manifest.revs
MATHLIB_REV="0df444a360eaa60ab8c11dca51a86af692955474"

# ---------------------------------------------------------------- machine minimums
MIN_FREE_DISK_GB=1500        # build outputs are ~1.1 TB; 2 TB recommended
REC_FREE_DISK_GB=1900
MIN_MEM_PLUS_SWAP_GB=96      # RAM + swap
MIN_FREE_INODES=5000000
MIN_OPEN_FILES=4096
MIN_MAX_MAP_COUNT=1048576   # vm.max_map_count; Ubuntu's default, AL2023/RHEL default is 65530

# ---------------------------------------------------------------- optional step 9: independent kernel
# lean4export writes the proof in a portable format; con-leche is an independently written kernel
# that checks it. Same tools and revisions as MIT's run (https://math.mit.edu/~drew/grh/).
CHECKER_LEAN_VERSION="4.36.0"                                    # con-leche is built with this Lean
CHECKER_LEAN_COMMIT="611c117bfaf7b7ae1cfcf246ce6fba31e8f509e9"   # git tag v4.36.0
CHECKER_LEAN_SHA256_x86_64="2b7ab1ed8b92d2e6abfaf41344823b510064dbc9c0260cac73eb496ab2dea6eb"
CHECKER_LEAN_SHA256_aarch64="35471998152191ef809418ce5bf61f8fc5f209e5e3be05b48bdc4949fdb3e726"
LEAN4EXPORT_URL="https://github.com/leanprover/lean4export"
LEAN4EXPORT_REV="15f6055e299ad5b89345e533cc2192f4cc00f659"       # tag v4.33.0; built with v$LEAN_VERSION
CONLECHE_URL="https://github.com/leanprover/con-leche"
CONLECHE_REV="cd2eceab2e9b10404c663b468639c8aa99d0d1f2"          # master as run by MIT
# expected/export-targets.txt: the declarations to export, from Deicyde/riemann-hypothesis
EXPORT_TARGETS_SHA256="9eeb2e5e55be4a78f6e4983fc950dba915b45ad8aeb7a02a32341927a89e05e8"
# For comparison only (not a pin): MIT's export of Main with the same tools and targets.
REFERENCE_EXPORT_SHA256="5ea74b912147c5c93cc2b6d70cc727cf908df2f62ac6a20480a3fa02f6be244e"
REFERENCE_EXPORT_SIZE=61570595788
# Used only with EXPORT_SOURCE=mit (step 9 checks MIT's published export instead of exporting).
REFERENCE_EXPORT_URL="https://math.mit.edu/~drew/grh/solution.ndjson.zst"
REFERENCE_EXPORT_ZST_SHA256="61a8938ad5f5e57397c1c0e3b954916af546d9004ade01c3555744a681b05381"
