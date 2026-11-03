# Plan: split upload and fetch in `check-dependency-track-action`

**Goal**: stop having every SBOM job wait for Dependency-Track processing. The 10 jobs in `pix` currently wait about 3 min each, so a run costs about 30 billed minutes on a private repo. After the change, upload jobs return right away and **one** job fetches all the results.

**Expected cost**: on push, ~10 × 1 min. On a PR, ~10 × 1 min + ~3 min.

---

## A. Action repo (`1024pix/check-dependency-track-action`)

### A1. `scripts/lib.sh` (new): shared functions
- Move the code that exists today in `upload.sh` into functions:
  - `deptrack_curl`: adds `X-Api-Key` and `--user` when Basic Auth is set.
  - `deptrack_wait_tokens`: polls **several** tokens in one loop, every 10 s, up to 25 retries in total.
  - `deptrack_lookup`: reads `name` and `version`, returns the risk score and policy counters.
  - `deptrack_markdown_row`: builds one table row.
- `upload.sh` and `fetch.sh` both call these functions, so the logic exists in one place only.
- Since this code is being rewritten anyway, also fix these TODOs: `set -euo pipefail`, quote `$token` and the URLs, remove the uninitialised counter `c`.

### A2. `scripts/upload.sh`: new `WAIT_FOR_STATUS` mode
- `WAIT_FOR_STATUS=true` (the default) keeps today's behaviour: poll, lookup, outputs `riskscore` / `status`, summary.
- `WAIT_FOR_STATUS=false` stops after `POST /api/v1/bom` and writes one output:
  ```
  upload={"name":"1024pix/pix-api","version":"refs/pull/12/merge","token":"<uuid>"}
  ```
  built with `jq -nc --arg`, so the JSON is always well formed. The token is not secret and is not masked (a masked value would be blanked in the job outputs).

### A3. `node/`, `golang/`, `python/` `action.yml`
- New input `wait_for_status`, default `'true'`, passed to the upload step through `env: WAIT_FOR_STATUS`.
- New output `upload_json`, mapped to `steps.upload.outputs.upload`.

### A4. `fetch/action.yml` + `scripts/fetch.sh` (new)

| Input | Notes |
|---|---|
| `url`, `key`, `basic_user`, `basic_password` | Same as the other actions. The key only needs `VIEW_PORTFOLIO`. |
| `projects` | One JSON line per project (the `upload` outputs). Empty lines are ignored, because a failed upload job gives an empty output. |

Steps:
1. Parse with `jq`. Check that each token is a UUID (regex) before putting it in a URL. Pass names and versions with `curl -G --data-urlencode`.
2. Call `dt_wait_tokens` on all tokens at once, so the total wait is the slowest project's, not the sum of all of them.
3. Wait 10 s, then call `dt_lookup` for each project.
4. Write the outputs:
   - `status`: the worst status (`fail` > `warn` > `pass`);
   - `results`: a JSON array with one entry per project;
   - `markdown`: the full table, written to `$GITHUB_OUTPUT` with a random heredoc delimiter;
   - and the same table to `$GITHUB_STEP_SUMMARY`.

The fetch job runs no third-party code, so getting the key there doesn't break the "secrets only in upload" rule.

### A5. Docs and checks
- Update the README (`wait`, `upload`, `fetch/`) and add an example in `example-action.yaml`.
- Run `shellcheck` and `actionlint`.
- Check in a test repo:
  1. `wait: true` gives the same result as today;
  2. `wait: false` + `fetch` gives correct statuses and table.
- Commit `feat: split upload and results fetch`, then pin the new SHA (with a `# vX` comment).

---

## B. `pix` repo: `.github/workflows/security.yml`

1. **Triggers**: `push: dev` + `pull_request: dev` with a `paths:` filter (`**/package-lock.json`, `.github/workflows/security.yml`), and `permissions: {}` at the top.
2. **In the 10 jobs**:
   - `wait: 'false'`;
   - remove `node_version` (the runner's Node is enough with `--package-lock-only`);
   - add the job output `upload: ${{ steps.<id>.outputs.upload }}`;
   - move the echo `${{ }}` lines to `env:`.
3. **New job `fetch_results`**:
   - `needs:` the 10 jobs, with `if: ${{ !cancelled() && github.event_name == 'pull_request' }}`;
   - `permissions: {}` (no checkout needed);
   - `projects:` gets the 10 `needs.*.outputs.upload` values on separate lines.
4. **`comment_on_pr`**:
   - `needs: fetch_results`, with `pull-requests: write` only;
   - writes the markdown with `printf '%s' "$MD" > "$RUNNER_TEMP/body.md"`, then `--body-file`.
   - The secret and the write token stay in **separate** jobs, which keeps least privilege.
5. Commit `chores: …` on `secu/update-deptrack-ci`.

This also fixes the review findings:
- #1: the trigger;
- #2: the `if:` on a job that doesn't exist;
- #3: `needs.X.outputs.*`;
- #4 and #5: literal `\n` and swapped columns;
- #6: `${{ }}` in `run:`;
- #7: top-level `permissions`.

---

## Trade-off to accept

On push to `dev`, the job summary no longer shows a risk score. The results only show up in Dependency-Track. If you want a summary on `dev` too, enable `fetch_results` for `push` as well (+~3 min).

## Open points

1. Local path of the action repo clone.
2. `projects` format: JSON lines through job outputs (recommended). The alternative is one artifact per job (`upload-artifact` / `download-artifact`), which needs two more actions to pin.

## References

- [Passing information between jobs](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/passing-information-between-jobs)
- [Multiline strings in `GITHUB_OUTPUT`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#multiline-strings)
- [Dependency-Track REST API](https://docs.dependencytrack.org/integrations/rest-api/)
- [GitHub Actions billing](https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions)
