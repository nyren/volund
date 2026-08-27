# Volund build system

[![pipeline](https://github.com/nyren/volund/actions/workflows/pipeline.yml/badge.svg?branch=master&event=push)](https://github.com/nyren/volund/actions/workflows/pipeline.yml)

**Volund** runs build steps in containers.

Volund offers a simple solution to achieve portable and reproducible builds.
Builds that are identical regardless if they run in the CI/CD pipeline or at a
developer's local machine.

Volund handles state between build steps. A developer can re-build a specific
step and a CI tool can visualize the build process by calling individual steps.

<img src="https://nyren.github.io/volund/example-core.svg" alt="Volund core demo" width="800">

## Concept

Take each build command and run it in a container instead of directly on the
local machine or build server. Do this for *all* commands required to build,
verify and upload your project artifacts and you have a truly portable build
system.

```
$ ./build.sh init
2026-08-27T18:07:44Z INFO image sh mirror.gcr.io/library/alpine:3.24.1
2026-08-27T18:07:44Z INFO ====> init
2026-08-27T18:07:44Z INFO cmd sh mkdir -p .build
```

Here `mkdir -p .build` was run in an alpine container, creating the `.build`
directory in the project repository.

Volund will volume-mount the project repository into the build container. The
build command reads and writes to the repository like it normally would.
However, it executes in the controlled environment of the build container.

```
. volund/lib/core

volund_image sh mirror.gcr.io/library/alpine:3.24.1

init() {
    volund_cmd sh mkdir -p .build
}

volund_main "$@"
```

A simple bash script, typically `build.sh`, drives the build process.

## License

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
