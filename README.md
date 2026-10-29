# Pix Action Dependency-Track Check

This GitHub action generates an SBOM (Software Bill Of Materials) of your project and uploads it to an OWASP Dependency-Track instance to perform a vulnerability check. To use it, you need an OWASP Dependency-Track instance and an API key that can reach its REST API from the Internet.

Dependency-Track lets you customize the vulnerability sources, follow the status of each project version in its web UI, and check the licenses of the libraries your project uses.

The project is uploaded to Dependency-Track using the repository name as `project` (suffixed with the sub-directory for monorepos) and the Git ref as `version`. The SBOM is generated directly in **CycloneDX JSON, spec v1.5**, supported by Dependency-Track v4.0.0 and higher. No XML to JSON conversion is needed anymore. During the test phase, the SBOM is validated with [CycloneDX CLI](https://github.com/CycloneDX/cyclonedx-cli) before upload.

## Fork history

This repo is a hard fork from https://github.com/Quobis/action-owasp-dependecy-track-check. The Quobis action is more generic (it supports Ruby, Maven, NuGet and PHP), which is not necessary for us.

## TODO

* [x] use pinned versions of cyclonedx-npm
* [x] use specific versions of npm
* [x] language : node
* [ ] wire `omit_devdependencies` (`--omit dev`)
* [ ] remove `--location` from curl calls (API key could follow a redirect to another host)
* [ ] choose the polling endpoint according to the Dependency-Track version (`/api/v1/bom/token/` vs `/api/v1/event/token/`)
* [ ] end of test phase: disable verbose output / SBOM dump, add a `validate_sbom` input
* [x] query dependency-track with basic auth
* [ ] language : python
* [x] language : go

## Input variables

- **url**: (required) URL of the OWASP Dependency-Track server.
- **key**: (required) API key used to access the OWASP Dependency-Track server.
  * This key is confidential, so [store it as a secret](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions) in the project settings. The example below uses the name `SECRET_OWASP_DT_KEY`.
  * Permissions needed: `BOM_UPLOAD`, `PROJECT_CREATION_UPLOAD`, `VIEW_PORTFOLIO`, nothing else.
- **directory**: (optional) for monorepos, the sub-directory containing `package-lock.json`. Default = `.`
- **node_version**: (optional) Node.js version to install with `actions/setup-node`. Default = empty, which keeps the runner's Node.js.
- **omit_devdependencies**: (optional) exclude dev dependencies from the SBOM. **Not wired yet.**
- **basic_user**: (optional) Basic Auth username, if Dependency-Track sits behind a reverse proxy requiring it.
- **basic_password**: (optional) Basic Auth password. Required if `basic_user` is set. Store it as a secret, and only use it over HTTPS.

## Output variables

- **riskscore**: the risk score calculated by OWASP Dependency-Track based on the vulnerabilities found. It can be used to make decisions, such as notifying the developer, or as the input of the next step of the workflow.
- **status**: `pass`, `warn` or `fail`, based on the Dependency-Track [policy violations](https://docs.dependencytrack.org/usage/policy-compliance/) of the project. Without policies configured in Dependency-Track, it is always `pass`.

The action also writes a summary (vulnerabilities by severity, risk score, status) to the [job summary](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#adding-a-job-summary) of the workflow run.

## Supported languages

- **Node.js**: `uses: 1024pix/check-dependency-track-action/node@<sha>`. A `package-lock.json` is required. The SBOM is built from the lockfile only (`--package-lock-only`): nothing is installed and no install scripts are run.
- **Python**: planned.
- **Go**: `uses: 1024pix/check-dependency-track-action/golang@<sha>`.

## How it works

1. `actions/setup-node`, only if `node_version` is set.
2. Generates `sbom.json` with `cyclonedx-npm` (pinned version), CycloneDX JSON v1.5.
3. `scripts/validate-sbom.sh`: downloads `cyclonedx-cli` (pinned version, SHA-256 checked) and validates the SBOM. This step does not receive the API key.
4. `scripts/upload.sh`: uploads the SBOM, waits for Dependency-Track to process it, then reads the project's risk score and policy violations. It sets the `riskscore` and `status` outputs and writes the job summary.

## How to use it

### Step 1: Get your Dependency-Track URL and API key

The key lets this action upload your project's `sbom.json` through the API.
+ Go to Configuration → Teams → Create Team to create a new team. This also creates an API key (a team can have several keys). More info [here](https://docs.dependencytrack.org/integrations/rest-api/).

Permissions needed: `BOM_UPLOAD`, `PROJECT_CREATION_UPLOAD`, `VIEW_PORTFOLIO`, nothing else.

### Step 2: Set up your workflow file

+ Create a `.github/workflows` directory in your repository if it doesn't already exist.
+ In this directory, create a file named `owasp-dt-check.yml`.
+ Copy the example below into your `owasp-dt-check.yml` file:

```yaml
name: Dependency-Track check

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read
  pull-requests: write # only needed for the PR comment step

jobs:
  dependency-track:
    runs-on: ubuntu-latest
    steps:
      # Pin actions by commit SHA
      - uses: actions/checkout@<sha> # v7

      # Generates an SBOM and uploads it to OWASP Dependency-Track
      - name: Generate SBOM and upload to OWASP Dependency-Track
        id: riskscoreFromDT
        uses: 1024pix/check-dependency-track-action/node@<sha>
        with:
          url: 'https://dtrack.example.com'
          key: '${{ secrets.SECRET_OWASP_DT_KEY }}'
          # directory: 'api'          # optional, for monorepos
          # node_version: '22.14.0'   # optional, default = runner's Node.js

      # Show the risk score output
      - name: Show the risk score
        env:
          SCORE: ${{ steps.riskscoreFromDT.outputs.riskscore }}
        run: echo "The risk score of the project is $SCORE"

      # Posts (or updates) a single comment on the PR
      # Does not work on PRs from forks: GITHUB_TOKEN is read-only there
      - name: Comment on the PR
        if: github.event_name == 'pull_request'
        env:
          GH_TOKEN: ${{ github.token }}
          SCORE: ${{ steps.riskscoreFromDT.outputs.riskscore }}
          STATUS: ${{ steps.riskscoreFromDT.outputs.status }}
          PR: ${{ github.event.pull_request.number }}
        run: |
          gh pr comment "$PR" --repo "$GITHUB_REPOSITORY" --edit-last --create-if-none \
            --body "Dependency-Track: **${STATUS}**, risk score **${SCORE}**"
```

Change `url` and `key` according to your Dependency-Track server. Keep the key in a secret.

About the PR comment step:
- It needs `pull-requests: write`. Remove the step and that permission if you only want the job summary.
- On PRs from forks, `GITHUB_TOKEN` is read-only, so the comment fails. Do **not** work around it with `pull_request_target` and a checkout of the PR code ([why](https://securitylab.github.com/resources/github-actions-preventing-pwn-requests/)).

The same example is available in `example-action.yaml` in this repository.

+ Commit the workflow file. The workflow runs on every push to `main` and on every pull request, and the results appear in your Dependency-Track server.
