# Adopting goosetest in Promptnook

Promptnook can keep domain modules such as `users/`, `workspaces/`, and
`db/` under the Goose project root. Configure separate targets for deterministic
domain cases and database-bound cases, with independent entry files and compiler
sidecars:

```sh
goosetest test --target core --profile optimized --offline
goosetest test --target database --profile debug
```

The core selection must not scan or link database-native inputs. A database
target should use an application-owned disposable database path and explicit
setup/cleanup. Do not run the ordinary `task migrate` command against the
default database from a framework fixture. The maintained
[Promptnook-shaped fixture](../integration/fixtures/promptnook/README.md) shows
the directory and target boundary using an unchanged workspace-tree serializer
snapshot and a small native resource stand-in.

That stand-in proves only that target-specific native linkage and fresh process
state work. It is not libSQL or Promptnook database parity. For real integration,
use an explicit Promptnook checkout and a separately provisioned disposable DB;
keep credentials, native dependency installation, migrations/reset policy, and
service readiness in application-owned orchestration. Keep the existing Python
HTTP baseline/candidate comparator as a separate application gate. Goosetest
owns selected target compilation and test execution, not application deployment.

## Optional explicit-checkout integration

Use this only after an application-owned `database` target exists and its tests
are configured for the local Turso path. The environment override keeps the
migration and test database inside a disposable directory; unset remote Turso
credentials so Task cannot select a remote database:

```sh
export PROMPTNOOK_GOOSE_ROOT=/path/to/promptnook/backend/goose
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
unset TURSO_DATABASE_URL TURSO_AUTH_TOKEN
export TURSO_LOCAL_PATH="$scratch/promptnook.db"

(cd "$PROMPTNOOK_GOOSE_ROOT" && task migrate)
goosetest test --project "$PROMPTNOOK_GOOSE_ROOT" --target core --profile optimized --offline
goosetest test --project "$PROMPTNOOK_GOOSE_ROOT" --target database --profile debug
# Run Promptnook's existing HTTP baseline/candidate comparator as a separate gate.
```

Keep comparator startup and service readiness in its current application runner.
Do not point this recipe at a shared or default database.
