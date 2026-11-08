# Changelog

All notable changes to this project are documented in this file.

## 0.1.1 — 2026-11-08

### Fixed

- `LlmToolkit.Composition` now honours the working directory from a
  `{module, cwd}` resolver entry on the first call, even when the resolver
  module has not been loaded yet. Previously the tuple's cwd was silently
  ignored and paths were resolved relative to the process working directory.
- `LlmToolkit.Composition.dispatch_recipe/2` now loads a resolver module before
  checking for its optional `dispatch_recipe/1` callback, so recipes are found
  on the first call as well.

The repository is now public.
