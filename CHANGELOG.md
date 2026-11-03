# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Security policy, changelog, code owners, editor config, and pull request template.

### Fixed

- Platform notes corrected to Ubuntu 26.04 LTS.

## [0.1.0] - 2026-11-03

### Added

- Idempotent single-node k3s bootstrap with kube-prometheus-stack and KEDA.
- Generated Grafana credentials stored only in-cluster; `grafana-password.sh` helper.
- `versions.lock` capturing installed component versions for reproducibility.
- Teardown script, CI linting (ShellCheck, yamllint, markdownlint), contribution guide.

[Unreleased]: https://github.com/vbhilare11/k8s-genomics-pipeline-bench/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/vbhilare11/k8s-genomics-pipeline-bench/releases/tag/v0.1.0
