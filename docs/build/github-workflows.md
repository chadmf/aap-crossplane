# GitHub Actions Workflows

This document describes the CI workflows in this repository. Workflow definitions live in [.github/workflows/](.github/workflows/).

## Overview

| Workflow file | Purpose |
|---------------|---------|
| [ci.yml](.github/workflows/ci.yml) | **CI** — Validates scaffold assets and builds the AAP Crossplane provider from the Upjet template + this scaffold. |

## Triggers

- **Push** to `main` or `master`
- **Pull request** targeting `main` or `master`

## CI workflow (ci.yml)

The workflow runs two jobs in parallel: **Validate** (scaffold-only checks) and **Build provider** (full provider build from template + scaffold).

### Job: Validate

Runs on `ubuntu-latest`. Validates assets in this repo only; no provider clone.

| Step | What it does |
|------|----------------|
| Checkout | Check out this repo (aap-crossplane). |
| ShellCheck | Install [ShellCheck](https://www.shellcheck.net/) and lint shell scripts under `hack/` (direct children only, e.g. `hack/prepare-aap.sh`, `hack/apply-post-generate-fixes.sh`). |
| Set up Python | Use Python 3.12. |
| Install yamllint | Install [yamllint](https://yamllint.readthedocs.io/). |
| Validate YAML | Run `yamllint -d relaxed` on `provider/config` and `provider/examples`. |
| Set up Node.js | Use Node.js 20. |
| Install markdownlint-cli | Install [markdownlint-cli](https://github.com/igorshubovych/markdownlint-cli). |
| Lint Markdown | Run markdownlint on `README.md`, `BUILD.md`, and `provider/README.md`. Runs with `continue-on-error: true`. |

