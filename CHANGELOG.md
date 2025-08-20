# Changelog

## Unreleased
* Bug fix: pip packages specified by file location are now correctly converted to "path"
  installs with Pixi.

## 0.2.30 (2025-08-19)
* `build=**cpython**` functionality updated for newer build strings in conda-forge.
* Special handling of `libstdcxx` for compatibility with Julia's `libstdc++.so`, plus
  corresponding `libstdcxx_version` preference.

## 0.2.29 (2025-05-14)
* Bug fix: detect actual libstdcxx version.
* Bug fix: comparing paths on weird filesystems.

## 0.2.28 (2025-04-09)
* Bug fix: remove lazy loading for backends, which is incompatible with precompilation.

## 0.2.27 (2025-04-06)
* When `add`ing or `rm`ing a dependency, if resolving fails then CondaPkg.toml is now reverted.
* Bug fixes.

## 0.2.26 (2025-03-03)
* Add `allowed_channels` preference to restrict which Conda channels can be used.
* Add `channel_priority` preference to control channel priority (strict/flexible/disabled).
* Add `channel_order` preference to specify channel ordering.
* Add `channel_mapping` preference to rename channels (useful for proxies/mirrors).
* Default channel priority is now `flexible`, or `strict` on pixi backends (previously `disabled`).
* Bug fixes in lazy loading.

## 0.2.25 (2025-02-18)
* Add `Pixi` and `SystemPixi` backends to allow using [Pixi](https://pixi.sh/latest/) to install packages.
* The `Pixi` backend is now the default on systems which have it available.

## 0.2.24 (2024-11-08)
* Add `pip_backend` preference to choose between `pip` and `uv`.
* Add `libstdcxx_ng_version` preference to override automatic version bounds.
* Add `openssl_version` preference to override automatic version bounds.
* Pip packages now support extras.

## 0.2.23 (2024-07-20)
* Pip packages are now installed using [`uv`](https://pypi.org/project/uv/) if it is installed.
* Special handling of `openssl` for compatibility with `OpenSSL_jll` if it is installed.

## 0.2.22 (2023-10-20)
* `pkg> conda run conda ...` now runs whatever conda executable CondaPkg is configured with.

## 0.2.21 (2023-09-30)
* Special handling of `python` with `build="**cpython**"`.

## 0.2.20 (2023-09-22)
* Shared envs are now not always fully reinstalled when resolving.

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
