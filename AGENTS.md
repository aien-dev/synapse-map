# synapse-map: agent brief

Development follows [Human-Directed Agentic Engineering (HDAE)](README.md#human-directed-agentic-engineering).
The README defines the human and agent responsibilities and cites Gregory M. Kurtzer's report.

Parent: aien-dev/synapse (`synapse.pin`). Language: seeded Omega, `src/*.om`, pinned by `omega.pin`.

## When to call it

- **Before starting a task**: `synapse-map where "<task in plain words>"`. Work in the top repo unless
  you have a concrete reason not to; read the `skills` it lists first. If the top two scores are
  close, read both repos' briefs before choosing. A `{"warn":...}` line means xerj was down and
  only the lexical ranking ran.
- **Before creating code that might already exist**: look at `similar` in the `where` output and at
  `synapse-map check` `duplicate_purpose` findings. Extend the existing repo instead of starting a
  second implementation.
- **Before saying a repo or file is missing**: `synapse-map tree` shows every repo in the map with its
  parent; a repo absent there is absent from the catalog the map was imported from, not proof it
  does not exist on GitHub. Re-import from a fresh catalog first.
- **After changing a `.crumb`** (yours or a new repo's): re-run `import` and `check`. `inferred_parent`
  findings clear when the child's crumb names its parent in `extensions.map`.
- **New standalone component**: `synapse-map new NAME --parent aien-dev/PARENT@SHA --purpose "..." --dir DIR`.
  Never put a new component inside an existing repo. Add `--publish --dry-run` to see every git and
  gh command; drop `--dry-run` only when you are authorised to create the GitHub repo and open the
  parent's draft PR.

## Rules for changing this repo

- stdout stays JSONL; human text goes to stderr. Exit codes follow the coordination contract.
- `map.jsonl` key order is a contract shared with synapse-mcp and synapse-board. Change it only
  through the integrator.
- Every `infer.tsv` and `topics.tsv` row cites its evidence. No guessed parents.
- Build only with `./build.sh` against the pinned omega-mv; run `tests/run.sh` before committing.
  NOT_RUN is not PASS.
