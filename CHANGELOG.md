# Changelog

## Unreleased
* Add `update` function and REPL command.
* Bug fixes.


## 0.2.16 (2023-01-23)
* Allow `JULIA_CONDAPKG_ENV` to specify the location of a shared Conda environment.
* The PkgREPL now supports the prefixes `@` for versions and `#` for build string.
* Bug fixes.

## 0.2.15 (2022-12-02)
* Special handling of `libstdcxx-ng` for compatibility with Julia's `libstdc++.so`.

## 0.2.14 (2022-11-11)
* Adds the `Current` backend, to use an existing Conda environment.

## 0.2.13 (2022-08-20)
* Adds offline mode (`JULIA_CONDAPKG_OFFLINE=yes`).
* Uses lock files to prevent two processes from updating the same environment concurrently.
