# Codacy Overall Coverage Gate

A GitHub composite action that fails the status check if a repository's
**overall** test coverage reported by Codacy falls below a configured
threshold. Codacy's own PR gate only checks diff/variation coverage (the
coverage of lines changed in the PR); this action fills the gap by checking
total repository coverage directly against the
[Codacy REST API](https://api.codacy.com/api/v3), using

```
GET /analysis/organizations/{provider}/{organization}/repositories/{repository}/commits/{commitSha}
```

and reading `coverage.totalCoveragePercentage` from the response.

## Prerequisites

- The repository must already be added to Codacy and have coverage reports
  uploaded (see Codacy's coverage reporter / `codacy-coverage-reporter`).
- A Codacy **account API token** with access to the repository. Generate one
  from Codacy account settings → API tokens, then add it as a GitHub Actions
  secret, e.g. `CODACY_API_TOKEN`.

## Usage

```yaml
name: Overall coverage gate

on:
  pull_request:

jobs:
  overall-coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Enforce overall repository coverage
        uses: your-org/overall-coverage-action@v1
        with:
          api-token: ${{ secrets.CODACY_API_TOKEN }}
          organization: your-org       # org/user as known by Codacy
          repository: your-repo        # repo name as known by Codacy
          min-coverage: '80'           # fail if overall coverage < 80%
```

Make this job a required status check in your branch protection rules so PRs
cannot merge when overall coverage is below the threshold.

## Inputs

| Input                  | Required | Default | Description                                                                                                    |
| ----------------------- | -------- | ------- | ---------------------------------------------------------------------------------------------------------------- |
| `api-token`             | yes      |         | Codacy account API token (`api-token` header). Store as a secret.                                                 |
| `provider`              | no       | `gh`    | Git provider identifier on Codacy: `gh`, `gl`, or `bb`.                                                            |
| `organization`          | yes      |         | Organization/user name as known by Codacy.                                                                        |
| `repository`            | yes      |         | Repository name as known by Codacy.                                                                               |
| `min-coverage`          | yes      |         | Minimum required overall coverage percentage (0-100).                                                             |
| `commit-sha`            | no       | (auto)  | Commit to check. Defaults to the PR head commit on `pull_request` events, else `github.sha`.                      |
| `fail-if-no-report`     | no       | `true`  | If `true`, fail when Codacy has no processed coverage report yet for the commit. If `false`, the check is skipped. |
| `max-attempts`          | no       | `10`    | Number of polling attempts while waiting for Codacy to finish processing a coverage report.                       |
| `retry-delay-seconds`   | no       | `15`    | Seconds between polling attempts.                                                                                 |

## Outputs

| Output     | Description                                               |
| ---------- | ----------------------------------------------------------- |
| `coverage` | Overall repository coverage percentage reported by Codacy. |

## How it works

1. Resolves the commit SHA to check (PR head commit by default).
2. Calls the Codacy API's `getCommit` endpoint for that commit, which
   returns overall coverage (`coverage.totalCoveragePercentage`) alongside
   quality metrics for that commit.
3. If no coverage report has been processed for that commit yet, it polls
   (`max-attempts` × `retry-delay-seconds`) before giving up.
4. Fails the step (and thus the check) if coverage is below `min-coverage`.

## Notes

- This checks **total** coverage at the commit, not the diff coverage of the
  PR — use it alongside (not instead of) Codacy's native diff-coverage gate
  if you want both guarantees.
- Make sure the coverage upload step in your CI (e.g.
  `codacy-coverage-reporter`) runs and completes **before** this action, on
  the same commit, so a report exists for Codacy to serve.
