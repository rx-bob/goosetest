<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo_dark_bg.svg">
    <img src="assets/logo_light_bg.svg" alt="goosetest" width="320">
  </picture>
</p>

## What is goosetest?

`goosetest` is an assertion library and test runner for [Goose](https://aardappel.github.io/goose/) (`v2026.3`). No manual test registration lists or macros—just write ordinary `test_*` functions and let `goosetest` discover, generate, and run them:

- **Zero-boilerplate discovery** for mirrored unit tests (`test/`) and integration suites (`integration/`).
- **Rich assertions & lifecycle hooks** (`assert_eq`, `check_eq`, per-case `Fixture`, `before_each` / `after_each`).

## Installation

Requires [Goose v2026.3](https://aardappel.github.io/goose/), `clang`, and [Task](https://taskfile.dev/).

```sh
git clone https://github.com/rx-bob/goosetest.git
cd goosetest
task install
```

Installs the `goosetest` CLI into `~/.local/bin` (override the prefix with `GOOSETEST_INSTALL_PREFIX=/your/prefix task install`).

## Configuration

Create a `goosetest_root.goose` entry point in your project root (pointing to your `goosetest` checkout):

```goose
import goosetest from "../goosetest";
import goosetest_generated.runner;

fn main() {
    exit(goosetest_generated::run_all());
}
```

By default, `goosetest` discovers unit tests in `test/` (mirroring `src/`) and integration tests in `integration/`. To keep tests in custom directories or define named build targets, add a `goosetest.json`:

```json
{
  "version": 1,
  "targets": [{
    "name": "core",
    "entry": "goosetest_core.goose",
    "tests": [{"path": "tests/request", "kind": "unit"}],
    "mirror": {"policy": "off", "pairs": []}
  }]
}
```

## Usage

Write ordinary `test_*` functions taking `t: goosetest::Test&` (and an optional `Fixture&`):

```goose
namespace calculator_test;

import goosetest;
import src.calculator;

fn test_addition(t: goosetest::Test&) {
    t.assert_eq(42, calculator::add(20, 22));
}
```

Run your suites with the CLI:

```sh
# Discover, build, and run all tests
goosetest test --project .

# List discovered test cases or filter by substring / suite
goosetest list --project .
goosetest test --project . --filter test_addition --fail-fast

# Run a configured target in debug or optimized mode
goosetest test --project . --target core --profile debug --offline
goosetest test --project . --target core --profile optimized --offline
```
