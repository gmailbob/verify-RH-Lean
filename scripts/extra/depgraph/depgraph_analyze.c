/*
 * depgraph_analyze: where the bulk of a proof lies, from depgraph's output.
 *
 * Usage:
 *   depgraph_analyze <dir> <root-name> [--depth D] [--min-pct P] [--query NAME]... [--dump]
 *
 * Reads <dir>/nodes.tsv and <dir>/edges.bin (format in DepGraph.lean). From the root
 * declaration it computes:
 *   - the set of declarations reachable from the root (its dependency cone);
 *   - the dominator tree of that cone. Node d dominates v if every dependency path from
 *     the root to v passes through d. The dominator subtree of d is everything that is
 *     needed *only* through d: its exclusive share of the proof. Cones overlap, because
 *     declarations share foundations; exclusive shares do not, and they sum to the total;
 *   - for each --query node: cone size, exclusive size, immediate dominator.
 * It prints the dominator tree down to --depth levels, showing children whose exclusive
 * share is at least --min-pct percent of the cone (default 0.5).
 *
 * Algorithm: Cooper, Harvey & Kennedy, "A Simple, Fast Dominance Algorithm" (iterate to a
 * fixed point in reverse postorder). Correct on graphs with cycles (inductive types point
 * to their constructors and back).
 * --dump prints "idom <node> <idom>" and "cone <node> <size>" for every reachable node,
 * for testing (test_analyze.py compares it with brute force).
 *
 * Build: cc -O2 -o depgraph_analyze depgraph_analyze.c
 *   or, with no system compiler, Lean's own:  leanc -O2 -o depgraph_analyze depgraph_analyze.c
 *   (the Lean toolchain ships clang and glibc libraries but no libc headers, so the few
 *   libc functions used are declared below when <stdio.h> is not available)
 */
#include <stddef.h>
#include <stdint.h>
#if __has_include(<stdio.h>)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#else
typedef struct _IO_FILE FILE;
typedef long ssize_t;
#define EOF (-1)
extern FILE *stderr;
FILE *fopen(const char *, const char *);
int fclose(FILE *);
size_t fread(void *, size_t, size_t, FILE *);
int fgetc(FILE *);
ssize_t getline(char **, size_t *, FILE *);
int printf(const char *, ...);
int fprintf(FILE *, const char *, ...);
int snprintf(char *, size_t, const char *, ...);
void *malloc(size_t);
void *calloc(size_t, size_t);
void *realloc(void *, size_t);
void free(void *);
void exit(int) __attribute__((noreturn));
unsigned long strtoul(const char *, char **, int);
int atoi(const char *);
double atof(const char *);
void qsort(void *, size_t, size_t, int (*)(const void *, const void *));
void *memset(void *, int, size_t);
void *memcpy(void *, const void *, size_t);
int memcmp(const void *, const void *, size_t);
int strcmp(const char *, const char *);
int strncmp(const char *, const char *, size_t);
char *strchr(const char *, int);
size_t strlen(const char *);
char *strdup(const char *);
#endif

#define UNDEF UINT32_MAX
#define NCAT 128   /* at most this many areas; the last slot collects the overflow */

static void die(const char *m) { fprintf(stderr, "depgraph_analyze: %s\n", m); exit(2); }
static void *xmalloc(size_t n) { void *p = malloc(n ? n : 1); if (!p) die("out of memory"); return p; }
static void *xcalloc(size_t n, size_t s) { void *p = calloc(n ? n : 1, s); if (!p) die("out of memory"); return p; }

static uint32_t N;
static char **name, **module, *kind, *user;
static uint8_t *cat;
static uint64_t *off; static uint32_t *adj;          /* forward CSR */
/* An area is the first two components of a module name ("Lib.Shimura", "New.Reduction"),
 * or the whole name when it has one component ("Main"). Areas are collected as they appear. */
static char *catName[NCAT];
static int nCat;

static uint8_t catOf(const char *mod) {
  const char *d1 = strchr(mod, '.');
  const char *d2 = d1 ? strchr(d1 + 1, '.') : NULL;
  size_t l = d2 ? (size_t)(d2 - mod) : strlen(mod);
  for (int c = 0; c < nCat; c++)
    if (strlen(catName[c]) == l && strncmp(catName[c], mod, l) == 0) return (uint8_t)c;
  if (nCat == NCAT - 1) { if (!catName[NCAT - 1]) catName[NCAT - 1] = strdup("other"); return NCAT - 1; }
  catName[nCat] = xmalloc(l + 1); memcpy(catName[nCat], mod, l); catName[nCat][l] = 0;
  return (uint8_t)nCat++;
}

static void readNodes(const char *path) {
  FILE *f = fopen(path, "r"); if (!f) die("cannot open nodes.tsv");
  size_t cap = 1 << 20; char *line = NULL; size_t lcap = 0; ssize_t len;
  name = xmalloc(cap * sizeof *name); module = xmalloc(cap * sizeof *module);
  kind = xmalloc(cap); user = xmalloc(cap); cat = xmalloc(cap);
  N = 0;
  while ((len = getline(&line, &lcap, f)) > 0) {
    if (line[len - 1] == '\n') line[--len] = 0;
    char *fld[5]; int k = 0; char *p = line;
    fld[k++] = p;
    while (k < 5 && (p = strchr(p, '\t'))) { *p++ = 0; fld[k++] = p; }
    if (k != 5) die("malformed nodes.tsv line");
    if (strtoul(fld[0], NULL, 10) != N) die("nodes.tsv indices not sequential");
    if (N == cap) {
      cap *= 2;
      name = realloc(name, cap * sizeof *name); module = realloc(module, cap * sizeof *module);
      kind = realloc(kind, cap); user = realloc(user, cap); cat = realloc(cat, cap);
      if (!name || !module || !kind || !user || !cat) die("out of memory");
    }
    name[N] = strdup(fld[1]); module[N] = strdup(fld[3]);
    kind[N] = fld[2][0]; user[N] = fld[4][0] == '1'; cat[N] = catOf(fld[3]);
    N++;
  }
  free(line); fclose(f);
}

static uint32_t rd32(FILE *f) {
  unsigned char b[4];
  if (fread(b, 1, 4, f) != 4) die("edges.bin truncated");
  return (uint32_t)b[0] | (uint32_t)b[1] << 8 | (uint32_t)b[2] << 16 | (uint32_t)b[3] << 24;
}

static void readEdges(const char *path) {
  FILE *f = fopen(path, "rb"); if (!f) die("cannot open edges.bin");
  char magic[4]; if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "DGR1", 4)) die("bad magic");
  if (rd32(f) != N) die("edges.bin node count differs from nodes.tsv");
  off = xmalloc((N + 1) * sizeof *off);
  size_t cap = 1 << 24; adj = xmalloc(cap * sizeof *adj); uint64_t E = 0;
  for (uint32_t i = 0; i < N; i++) {
    off[i] = E;
    uint32_t d = rd32(f);
    if (E + d > cap) { while (E + d > cap) cap *= 2; adj = realloc(adj, cap * sizeof *adj); if (!adj) die("out of memory"); }
    for (uint32_t k = 0; k < d; k++) {
      uint32_t j = rd32(f);
      if (j >= N) die("edge target out of range");
      adj[E++] = j;
    }
  }
  off[N] = E;
  if (fgetc(f) != EOF) die("trailing bytes in edges.bin");
  fclose(f);
}

/* ------------------------------------------------------------------ analysis state */
static uint32_t *po;        /* postorder number, UNDEF if unreachable */
static uint32_t *byPo;      /* node with postorder number k */
static uint32_t R;          /* reachable count */
static uint32_t *idom;
static uint64_t *poff; static uint32_t *pred;   /* predecessor CSR (reachable part) */

static void dfsPostorder(uint32_t root) {
  po = xmalloc(N * sizeof *po); for (uint32_t i = 0; i < N; i++) po[i] = UNDEF;
  byPo = xmalloc(N * sizeof *byPo);
  uint8_t *seen = xcalloc(N, 1);
  uint32_t *stk = xmalloc((N + 1) * sizeof *stk); uint64_t *it = xmalloc((N + 1) * sizeof *it);
  int64_t sp = 0; R = 0;
  stk[0] = root; it[0] = off[root]; seen[root] = 1;
  while (sp >= 0) {
    uint32_t v = stk[sp];
    if (it[sp] < off[v + 1]) {
      uint32_t w = adj[it[sp]++];
      if (!seen[w]) { seen[w] = 1; sp++; stk[sp] = w; it[sp] = off[w]; }
    } else {
      po[v] = R; byPo[R] = v; R++; sp--;
    }
  }
  free(seen); free(stk); free(it);
}

static void buildPreds(void) {
  uint32_t *cnt = xcalloc(N + 1, sizeof *cnt);
  for (uint32_t v = 0; v < N; v++) if (po[v] != UNDEF)
    for (uint64_t e = off[v]; e < off[v + 1]; e++) cnt[adj[e]]++;
  poff = xmalloc((N + 1) * sizeof *poff); poff[0] = 0;
  for (uint32_t v = 0; v < N; v++) poff[v + 1] = poff[v] + cnt[v];
  pred = xmalloc((poff[N] ? poff[N] : 1) * sizeof *pred);
  memset(cnt, 0, (N + 1) * sizeof *cnt);
  for (uint32_t v = 0; v < N; v++) if (po[v] != UNDEF)
    for (uint64_t e = off[v]; e < off[v + 1]; e++) { uint32_t w = adj[e]; pred[poff[w] + cnt[w]++] = v; }
  free(cnt);
}

static uint32_t intersect(uint32_t a, uint32_t b) {
  while (a != b) {
    while (po[a] < po[b]) a = idom[a];
    while (po[b] < po[a]) b = idom[b];
  }
  return a;
}

static int dominators(uint32_t root) {
  idom = xmalloc(N * sizeof *idom); for (uint32_t i = 0; i < N; i++) idom[i] = UNDEF;
  idom[root] = root;
  int rounds = 0, changed = 1;
  while (changed) {
    changed = 0; rounds++;
    for (int64_t k = (int64_t)R - 2; k >= 0; k--) {        /* reverse postorder, root (R-1) skipped */
      uint32_t b = byPo[k], nd = UNDEF;
      for (uint64_t e = poff[b]; e < poff[b + 1]; e++) {
        uint32_t p = pred[e];
        if (idom[p] == UNDEF) continue;
        nd = (nd == UNDEF) ? p : intersect(p, nd);
      }
      if (nd != idom[b]) { idom[b] = nd; changed = 1; }
    }
  }
  return rounds;
}

/* cone of v (all nodes reachable from v, v included): returns (all, user) */
static uint8_t *coneMark;
static void cone(uint32_t v, uint64_t *all, uint64_t *usr) {
  static uint32_t *q; if (!q) q = xmalloc(N * sizeof *q);
  memset(coneMark, 0, N);
  uint64_t h = 0, t = 0; q[t++] = v; coneMark[v] = 1; *all = 0; *usr = 0;
  while (h < t) {
    uint32_t x = q[h++]; (*all)++; *usr += user[x];
    for (uint64_t e = off[x]; e < off[x + 1]; e++) { uint32_t w = adj[e]; if (!coneMark[w]) { coneMark[w] = 1; q[t++] = w; } }
  }
}

static uint64_t *sub, *subUser, (*subCat)[NCAT];
static uint64_t *coff; static uint32_t *child;  /* dominator-tree children CSR */

static int cmpSub(const void *a, const void *b) {
  uint64_t x = sub[*(const uint32_t *)a], y = sub[*(const uint32_t *)b];
  return x < y ? 1 : x > y ? -1 : 0;
}

static const char *kindName(char k) {
  switch (k) {
    case 't': return "thm"; case 'd': return "def"; case 'i': return "inductive"; case 'c': return "ctor";
    case 'r': return "rec"; case 'o': return "opaque"; case 'a': return "AXIOM"; case 'q': return "quot";
    default: return "decl";
  }
}

static void printNode(uint32_t v, int depth, int maxDepth, double minPct) {
  double pct = 100.0 * (double)sub[v] / (double)R;
  printf("%*s%s %s  [%s]  exclusive %lu (%.2f%%), user-written %lu", 2 * depth, "",
         kindName(kind[v]),
         name[v], module[v], (unsigned long)sub[v], pct, (unsigned long)subUser[v]);
  /* the three largest areas in this subtree */
  int best[3] = {-1, -1, -1};
  for (int c = 0; c < NCAT; c++) {
    for (int s = 0; s < 3; s++) {
      if (best[s] < 0 || subCat[v][c] > subCat[v][best[s]]) {
        for (int u = 2; u > s; u--) best[u] = best[u - 1];
        best[s] = c; break;
      }
    }
  }
  printf("  {");
  for (int s = 0; s < 3; s++) if (best[s] >= 0 && catName[best[s]] && subCat[v][best[s]] > 0)
    printf("%s%s %.0f%%", s ? ", " : "", catName[best[s]], 100.0 * (double)subCat[v][best[s]] / (double)sub[v]);
  printf("}\n");
  if (depth >= maxDepth) return;
  uint64_t n = coff[v + 1] - coff[v];
  uint32_t *ch = xmalloc((n ? n : 1) * sizeof *ch);
  memcpy(ch, child + coff[v], n * sizeof *ch);
  qsort(ch, n, sizeof *ch, cmpSub);
  uint64_t restN = 0, restSize = 0;
  for (uint64_t k = 0; k < n; k++) {
    if (100.0 * (double)sub[ch[k]] / (double)R >= minPct) printNode(ch[k], depth + 1, maxDepth, minPct);
    else { restN++; restSize += sub[ch[k]]; }
  }
  if (restN) printf("%*s+ %lu smaller children, %lu nodes in total (%.2f%%)\n", 2 * depth + 2, "",
                    (unsigned long)restN, (unsigned long)restSize, 100.0 * (double)restSize / (double)R);
  free(ch);
}

static int32_t findName(const char *s) {
  for (uint32_t i = 0; i < N; i++) if (strcmp(name[i], s) == 0) return (int32_t)i;
  return -1;
}

int main(int argc, char **argv) {
  if (argc < 3) die("usage: depgraph_analyze <dir> <root-name> [--depth D] [--min-pct P] [--query NAME]... [--dump]");
  const char *dir = argv[1], *rootName = argv[2];
  int maxDepth = 8, dump = 0; double minPct = 0.5;
  const char *queries[256]; int nq = 0;
  for (int a = 3; a < argc; a++) {
    if (!strcmp(argv[a], "--depth") && a + 1 < argc) maxDepth = atoi(argv[++a]);
    else if (!strcmp(argv[a], "--min-pct") && a + 1 < argc) minPct = atof(argv[++a]);
    else if (!strcmp(argv[a], "--query") && a + 1 < argc && nq < 256) queries[nq++] = argv[++a];
    else if (!strcmp(argv[a], "--dump")) dump = 1;
    else die("unknown argument");
  }
  char path[4096];
  snprintf(path, sizeof path, "%s/nodes.tsv", dir); readNodes(path);
  snprintf(path, sizeof path, "%s/edges.bin", dir); readEdges(path);
  int32_t root = findName(rootName); if (root < 0) die("root not found");

  dfsPostorder((uint32_t)root);
  buildPreds();
  int rounds = dominators((uint32_t)root);

  /* subtree sizes: a dominator has a larger postorder number than what it dominates */
  sub = xcalloc(N, sizeof *sub); subUser = xcalloc(N, sizeof *subUser); subCat = xcalloc(N, sizeof *subCat);
  for (uint32_t k = 0; k < R; k++) { uint32_t v = byPo[k]; sub[v] = 1; subUser[v] = user[v]; subCat[v][cat[v]] = 1; }
  for (uint32_t k = 0; k + 1 < R; k++) {
    uint32_t v = byPo[k], d = idom[v];
    if (d == UNDEF || po[d] <= po[v]) die("internal error: dominator order");
    sub[d] += sub[v]; subUser[d] += subUser[v];
    for (int c = 0; c < NCAT; c++) subCat[d][c] += subCat[v][c];
  }
  if (sub[root] != R) die("internal error: subtree sizes do not sum to the cone");

  /* children CSR */
  uint32_t *cc = xcalloc(N + 1, sizeof *cc);
  for (uint32_t k = 0; k + 1 < R; k++) cc[idom[byPo[k]]]++;
  coff = xmalloc((N + 1) * sizeof *coff); coff[0] = 0;
  for (uint32_t v = 0; v < N; v++) coff[v + 1] = coff[v] + cc[v];
  child = xmalloc((coff[N] ? coff[N] : 1) * sizeof *child); memset(cc, 0, (N + 1) * sizeof *cc);
  for (uint32_t k = 0; k + 1 < R; k++) { uint32_t v = byPo[k], d = idom[v]; child[coff[d] + cc[d]++] = v; }
  free(cc);
  coneMark = xmalloc(N);

  if (dump) {
    for (uint32_t k = 0; k < R; k++) { uint32_t v = byPo[k]; printf("idom %s %s\n", name[v], name[idom[v]]); }
    for (uint32_t k = 0; k < R; k++) { uint32_t v = byPo[k]; uint64_t a, u; cone(v, &a, &u); printf("cone %s %lu\n", name[v], (unsigned long)a); }
    return 0;
  }

  uint64_t usersAll = 0, usersReach = 0; for (uint32_t v = 0; v < N; v++) { usersAll += user[v]; if (po[v] != UNDEF) usersReach += user[v]; }
  printf("nodes: %u (user-written %lu)   edges: %lu\n", N, (unsigned long)usersAll, (unsigned long)off[N]);
  printf("cone of %s: %u nodes (%.1f%% of all), user-written %lu (%.1f%%)\n", rootName, R, 100.0 * R / N,
         (unsigned long)usersReach, usersAll ? 100.0 * usersReach / usersAll : 0.0);
  printf("not needed by the root: %u nodes, user-written %lu\n", N - R, (unsigned long)(usersAll - usersReach));
  printf("dominator computation: %d rounds to fixed point\n\n", rounds);

  if (nq) {
    printf("%-74s %12s %8s %12s %8s  %s\n", "query", "cone", "cone%", "exclusive", "excl%", "immediate dominator");
    for (int q = 0; q < nq; q++) {
      int32_t v = findName(queries[q]);
      if (v < 0) { printf("%-74s not found\n", queries[q]); continue; }
      if (po[v] == UNDEF) { printf("%-74s not reachable from the root\n", queries[q]); continue; }
      uint64_t a, u; cone((uint32_t)v, &a, &u);
      printf("%-74s %12lu %7.2f%% %12lu %7.2f%%  %s\n", queries[q], (unsigned long)a, 100.0 * a / R,
             (unsigned long)sub[v], 100.0 * sub[v] / R, (uint32_t)v == (uint32_t)root ? "-" : name[idom[v]]);
    }
    printf("\n");
  }
  printf("dominator tree (exclusive share = needed only through that declaration):\n");
  printNode((uint32_t)root, 0, maxDepth, minPct);
  return 0;
}
