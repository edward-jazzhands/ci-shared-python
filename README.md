Shared CI/CD scripts and config files for Python projects.

Add this to your Justfile/Makefile/etc:

```make
sync-ci:
  curl -fsSL https://raw.githubusercontent.com/edward-jazzhands/ci-shared-python/main/sync.sh | bash
```

Run that in a project root and it will sync the contents of this repo's `.github` directory into the project's `.github` directory.

This will overwrite any existing files, but it will not delete any files that are not in this repo.