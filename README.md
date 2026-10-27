Child of [aien-dev/synapse](https://github.com/aien-dev/synapse) at `099a980fedab8a6797bbf0358b8c5502c8045142` (see `synapse.pin`).

# synapse-map

The repo map for AI lanes working on the aien-dev organisation. It answers three questions an agent
has before touching code: which repository does this task belong to, what is that repository's
parent, and is the tree of repositories consistent. It also scaffolds new standalone components as
their own repositories, connected to a parent.

`synapse-map` is one binary written in seeded Omega (`src/*.om`), compiled by the pinned `omc`
(`omega.pin`). There is no interim host code in the binary. `tests/run.sh` uses `sh`, `jq` and
`python3` only as checkers.

## Commands

All output on stdout is JSONL; human text goes to stderr. The state home is `--home DIR`, else
`$AIEN_COORD_HOME`, else `$HOME/.local/state/aien-coord`.

| command | does | exit |
|---|---|---|
| `import --catalog FILE [--extra FILE] [--crumbs DIR] [--infer FILE]` | writes `<home>/map.jsonl` atomically, one record per repo, prints `{"ok":true,"repos":N,...}` | 0, 65 malformed input, 4 missing file |
| `index [--topics F] [--skills F] [--xerj IP:PORT] [--index NAME]` | rebuilds the xerj index (default `aien-map` on 127.0.0.1:9200) from the map, topics and skills | 0, 75 xerj down |
| `where TASK [--limit N] [--no-xerj] ...` | ranked repos: `{"repo","score","purpose","parent","why","skills":[..],"similar":[..]}` | 0, 4 no match |
| `tree [--text]` | parent tree as JSONL nodes (or indented text on stdout with `--text`) | 0 |
| `check [--min-jaccard MILLI] [--no-xerj] ...` | findings `{"kind":...}`: orphan, missing_parent, archived_parent, fork_parent, inferred_parent, duplicate_purpose | 0 clean, 1 findings |
| `new NAME --parent OWNER/REPO[@REF] --purpose TEXT --dir DIR [--layer L] [--publish [--dry-run]]` | scaffolds `.crumb`, `.goals.json`, `README.md`, `AGENTS.md`, `synapse.pin` (synapse children), `PARENT-PR.md`, runs `crumb validate` | 0, 1 crumb invalid, 64 DIR already has a .crumb |

Exit codes: 0 ok, 1 findings, 4 not found, 64 usage, 65 malformed, 70 internal, 75 temporary.

### map.jsonl record

Keys in this order:

```
{"repo":"aien-dev/NAME","parent":"aien-dev/P@ref"|null,"parent_status":"CONFIRMED"|"INFERRED"|"ROOT"|"NONE",
 "purpose":..,"layer":..,"archived":bool,"fork":bool,"default_branch":..|null,"pushed_at":..|null,
 "brief":..,"source":"catalog"|"extra","infer_rule":"L<n> <pattern>"|"crumb"|null}
```

A parent is CONFIRMED only when the repository's own `.crumb` names it in `extensions.map.parent`.
Otherwise the first matching row of `infer.tsv` decides (INFERRED, ROOT or NONE), and `check`
reports every INFERRED parent until the child's crumb confirms it. A parent without an explicit ref
is pinned to the parent's `default_branch`, or `@unknown` when the map does not know it.

### Rule and topic files

- `infer.tsv`: `pattern<TAB>parent<TAB>why[<TAB>layer]`. Patterns are case-insensitive globs on the
  repo name, or `desc:<substring>` on the purpose. The first match wins.
- `topics.tsv`: `repo<TAB>terms<TAB>evidence`. Extra search terms a repository's description does not
  carry (for example `tls` for omega-mv, whose TLS 1.3 client lives in `om/tls/`), each with a
  pinned source path as evidence.

Both files are read from the binary's directory unless `--infer`/`--topics` name others.

### where scoring

Lexical: the sum, over query terms shared with a repo, of `idf(term) * (1 + boost)`, where boost is 1
for terms from the repo name and `topics.tsv`, and idf is `1000 + 1000 * log2((N+1)/(df+1))`.
Archived repos score half. When xerj answers, its semantic score is combined 6:4 with the lexical
score (each scaled to its maximum); when xerj is unreachable `where` prints
`{"warn":"xerj unreachable"}` first and ranks lexically.

### new --publish

After the scaffold passes `crumb validate`, `--publish` runs, as
`/usr/bin/env HOME=$HOME PATH=$HOME/.local/bin:/usr/bin:/bin ...`:
`git init`/`add`/`commit -s` in DIR, `gh repo create ORG/NAME --public --description PURPOSE --source DIR --push`,
`git clone` of the parent into `DIR.parent`, branch `connected/NAME`, the README line under
`## Connected repos` (section created when absent), `commit -s`, `push`, and
`gh pr create --draft` with `PARENT-PR.md` as the body. `--dry-run` prints each argv as
`{"argv":[...]}` and the README edit as `{"edit":..,"line":..}` without running anything.

## Build and test

```
./build.sh /path/to/omega-mv out/synapse-map   # checks omega.pin (HEAD and omc sha256) first
OMEGA_SRC=/path/to/omega-mv sh tests/run.sh
```

Tests run against throwaway homes. Cases that need xerj (127.0.0.1:9200) or the `crumb` CLI print
NOT_RUN when those are absent (as on CI); NOT_RUN is never counted as a pass.

## Connected repos

- Parent: [aien-dev/synapse](https://github.com/aien-dev/synapse)
- [aien-dev/synapse-claims](https://github.com/aien-dev/synapse-claims): claims ledger CLI
- [aien-dev/synapse-pulse](https://github.com/aien-dev/synapse-pulse): collision and lease reconciler
- [aien-dev/synapse-mcp](https://github.com/aien-dev/synapse-mcp): MCP server over claims, map and pulse
- [aien-dev/synapse-board](https://github.com/aien-dev/synapse-board): generated BOARD renderer
- [aien-dev/omega-mv](https://github.com/aien-dev/omega-mv): the language and compiler (`omega.pin`)

## License

Apache-2.0 WITH LLVM-exception, as the parent (`LICENSE`).
