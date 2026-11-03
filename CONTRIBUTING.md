# Contributing

## Branching

- `main` is protected. All changes land via pull request with passing CI.
- Branch names: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `exp/<experiment-id>`, `chore/<topic>`.
- One logical change per PR. Squash-merge; the PR title becomes the commit message.

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/). Examples:

- `feat(workload): add synthetic FASTQ generator`
- `fix(cluster): make bootstrap idempotent on re-run`
- `docs(experiments): describe E1 autoscaling protocol`
- `exp(E1): KEDA vs HPA, 3 replicates, 2026-11-10`

## Releases

Semantic versioning. Tags `vMAJOR.MINOR.PATCH`; each tag has a GitHub Release and a
`CHANGELOG.md` entry. Experiment campaigns referenced in the paper are tagged so a reader
can check out the exact code that produced a figure.

## Experiments

Every run records: git SHA, `cluster/versions.lock`, parameters, start/end timestamps,
and raw Prometheus exports under `results/<experiment-id>/`. Figures are regenerated
from raw data by script, never edited by hand.
