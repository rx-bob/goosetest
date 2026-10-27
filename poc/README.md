# Historical prototypes

This directory preserves the experiments behind the framework. It is excluded
from shipping-source style checks and the supported test workflow.

Start with [the research notes](goosetest_framework_research.md). The notes use
prototype APIs and describe experiments, not release promises. In particular:

- The old scanner silently stops at fixed case/file capacities and suppresses
  some read failures. The maintained discovery pipeline reports incomplete runs.
- The prototype summary can display failed tests while the process exits 0.
- Several files violate declaration, spacing, 70-line function and 500-line file
  rules; excluding this directory does not waive those rules for shipping code.
- The generator retains an obsolete machine-specific `docs/example_project`
  path. Do not treat its historical invocation as a supported developer command.
- Cleanup after a recoverable assertion does not imply cleanup after abort,
  explicit exit, process death, a deadline, or a native failure.
- Timing and zero-overhead statements were prototype observations. They are not
  performance guarantees or current benchmark results.
- Tags, repetitions, contained workers and the nested describe DSL remain outside
  the first-release API.

Use the [maintained example](../examples/basic/README.md) and
[developer commands](../README.md) for supported behavior. The prototypes are not
an alternate runtime to copy into a consumer project.
