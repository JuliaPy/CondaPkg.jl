# Changelog

## 0.2.19 (2023-09-21)
* Now configurable using preferences.

## 0.2.18 (2023-03-22)
* Lock file is always shown when locked.

## 0.2.17 (2023-01-27)
* Adds named shared environments: `JULIA_CONDAPKG_ENV=@<name>`.
* Add `update` function and PkgREPL command.
* The shared environment from using the `Current` backend is treated the same as other
  shared environments.
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
