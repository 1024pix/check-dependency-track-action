## Phase 0: Decisions and prerequisites

- Repo: a new repo such as 1024pix/dtrack-action, rather than continuing the fork. Archive the fork once migration is done.
- Dependency Track: note your server version. It determines which CycloneDX spec version to use (1.5 or 1.6) and which polling endpoint exists (/api/v1/event/token/{token} in recent versions vs the older /api/v1/bom/token/{token}).
- API key (least privilege): BOM_UPLOAD, PROJECT_CREATION_UPLOAD, VIEW_PORTFOLIO, nothing else.
- TLS: decide whether --insecure is ever needed. If it isn't, remove it completely.

## Phase 1: Shared script scripts/upload.sh

- Bash with set -euo pipefail (no more dash pitfalls).
- Inputs come through env: .* }} inside run:, becausethat allows script injection (GitHub docs).
- echo "::add-mask::$DTRACK_KEY" at the top, and no curl --verbose.
- Steps:
  a. Upload bom.json (autoCtVersion).
  b. Get the token, failing if it's empty.
  c. Poll with a configurab
  d. Look up the project, then read lastInheritedRiskScore.
  e. Write riskscore and prUT.
- Optional: a fail_on_risk_score input that fails the job above a threshold.

## Phase 2: node/action.yml (do this first, it's Pix's main use)

```yml
name: 'Dependency Track – Node'
inputs:
  url:              { required: true }
  key:              { requi
  directory:        { default: '.' }
  project_name:     { defauo>[-<directory>]
  project_version:  { defau}' }
  node_version:     { default: '' }   # empty = keep the runner's Node
  timeout_retries:  { default: '30' }
outputs:
  riskscore: { value: '${{ core }}' }
runs:
  using: composite
  steps:
    - if: inputs.node_versi
      uses: actions/setup-node@<SHA> # vX
      with: { node-version:}}' }
    - shell: bash
      working-directory: ${
      run: |
        test -f package-loc:package-lock.json notfound"; exit 1; }
        npx --yes @cyclonedx/cyclonedx-npm@<pinned> --package-lock-only \
          --output-format JSON --spec-version 1.5 --output-file bom.json
    - id: upload
      shell: bash
      working-directory: ${{ inputs.directory }}
      env:
        DTRACK_URL: ${{ inputs.url }}                                                DTRACK_KEY: ${{ inp
        # ...
      run: ${{ github.action_path }}/../scripts/upload.sh
```

- --package-lock-only means nothing is installed and no install scripts run.
- Optionally add --omit dev as an input if you only want production dependencies.


## Phase 3: python/action.yml

- Inputs: mode (requirements | poetry | pipenv, default requirements), file, python_version (optional, uses setup-python).
- Generation: pipx run cyclonedx-bom==<pinned> <mode> [file] --of JSON --sv 1.5 -o bom.json. pipx is preinstalled on GitHub runners, which avoids PEP 668 issues.
- Warn (::warning::) if requirements.txt has unpinned dependencies, since Dependency Track can't match CVEs without versions.

## Phase 4: go/action.yml

- Use CycloneDX/cyclonedx-gomod, which replaces the archived ozonru/cyclonedx-go: go install github.com/CycloneDX/cyclonedx-gomod/cmd/cyclonedx-gomod@<pinned>.
- cyclonedx-gomod mod -json -output bom.json (check the spec-version flag with -h).
- go_version is optional (uses setup-go).

## Phase 5: CI and tests

- fixtures/{node,python,go}: small projects with a lockfile.
- PR workflow:
  - actionlint, shellcheck,for workflows).
  - Each action with upload: false (dry-run input), then validate the BOM with cyclonedx-cli validate.
- Integration workflow (manual or nightly) against your real Dependency Track, with a dedicated test key
- Set permissions: contents: read on every workflow.

## Phase 6: Dependency maintenance

- Dependabot github-actions with directories: ["/", "/node", "/python", "/go"]
  keeps the setup-* SHAs up
- Renovate regex manager, or a quarterly manual check, for the pinned tools
  (cyclonedx-npm, cyclonedx

## Phase 7: Release and migration

- Tag v1.0.0 plus a moving v1 tag. Callers pin the SHA.
- In the README, add a migr-ci → uses:1024pix/dtrack-action/node@…, and so on.
- Find the Pix repos that use the old fork (gh search code "action-owasp-dependecy-track-check" --owner 1024pix), migrate them, then
  archive the fork.

## Suggested order

Phase 1 + 2 → test on a Pix and 4 → Phases 6 and 7.

Open questions:
1. What's the repo name?
2. Which Dependency Track version (it decides spec 1.5 vs 1.6 and the polling endpoint)?
3. Do you want a fail_on_risk_score threshold?
4. Production dependencies only, or dev dependencies too?


