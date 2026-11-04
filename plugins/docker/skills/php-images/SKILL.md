---
description: |
    Use this skill when working with Specsnl PHP Docker images. It covers what the images are, their repository
    structure and variants, which PHP versions are maintained, and how to locate sibling images both on GitHub
    and locally.
name: php-images
---

# PHP Images Skill

This skill provides information about the PHP images used in the Specsnl projects, including where to find the source
files and how to locate sibling images for other PHP versions.

## What are the PHP images?

The PHP images are Docker images that serve as the base for the various PHP environments used in Specsnl projects. These
images are built on top of official PHP images and include additional dependencies and configurations specific to our
needs.

Each PHP image repository follows a consistent structure with three main Dockerfiles (variants):

- `fpm/Dockerfile`: The Dockerfile for the FPM variant of the image.
- `apache/Dockerfile`: The Dockerfile for the Apache variant of the image.
- `frankenphp/Dockerfile`: The Dockerfile for the FrankenPHP variant of the image.

Furthermore, there is a `files` directory that contains additional files used during the build process, such as
configuration files and scripts.

- `files/general`: Contains files that are shared across all PHP Dockerfiles.
- `files/<variant_name>`: Contains files specific to the `<variant_name>` variant of the image.

Not every repository ships every variant: a variant is only present when that PHP version supports it (e.g.
FrankenPHP requires PHP 8.2+, so `php74` has no `frankenphp` variant). Check which `<variant>/Dockerfile` files a
repository actually contains instead of assuming all three.

## Maintained PHP versions

Specsnl maintains an image for **every** PHP image repository in the `specsnl` GitHub organisation, not just the
most recent PHP versions. End-of-life PHP versions (e.g. PHP 7.4) are still maintained as long as their repository
exists. Do not use endoflife.date or any "last N versions" rule to decide which versions are in scope.

A PHP image repository is named `php<major><minor>`: `php` followed by exactly two digits, e.g. `php85`, `php84`,
`php83`, `php80` or `php74`. To list the current set, query the organisation and keep the non-archived repositories
whose name matches `^php[0-9]{2}$`:

```bash
gh repo list specsnl --limit 1000 --no-archived --json name \
    --jq '[.[].name | select(test("^php[0-9]{2}$"))] | sort | reverse | .[]'
```

When the `gh` CLI is unavailable, use a GitHub MCP repository search (`org:specsnl php in:name`) and apply the same
name filter. When neither works, fall back to the local sibling directories (see below) and record that the set may
be incomplete.

The newest version is the repository with the highest number. If PHP has released a newer version but its Specsnl
repository has not been created yet, that version is not maintained yet: the highest existing repository is the
latest.

## Where can I find the source files on GitHub?

The source files for the PHP images can be found in the repositories that follow the following structure:
`https://github.com/specsnl/php<major><minor>`. For example, for PHP 8.5, the source files are located in
`https://github.com/specsnl/php85`.

## How are the published images named and tagged?

The built images are published to the GitHub Container Registry (GHCR). The current (newer) naming scheme
encodes the variant and build target as path segments under the repository, and uses the tag only for the
version:

`ghcr.io/specsnl/php<major><minor>[/<variant>][/<target>]:<version>`

- `<variant>`: omitted for the FPM variant; otherwise `apache` or `frankenphp`.
- `<target>`: omitted for the `runtime` (production) target; otherwise `builder` (adds development tooling
  such as Composer and Xdebug) or `builder_nodejs` (builder plus Node.js).
- `<version>`: `latest`, a release tag (e.g. `0.5.5`), `main`, or `pr-<number>`.

Examples for PHP 8.5:

```bash
docker pull ghcr.io/specsnl/php85:latest                      # fpm runtime
docker pull ghcr.io/specsnl/php85/builder:latest              # fpm builder
docker pull ghcr.io/specsnl/php85/builder_nodejs:latest       # fpm builder + Node.js
docker pull ghcr.io/specsnl/php85/apache:latest               # apache runtime
docker pull ghcr.io/specsnl/php85/apache/builder:latest       # apache builder
docker pull ghcr.io/specsnl/php85/frankenphp:latest           # frankenphp runtime
docker pull ghcr.io/specsnl/php85/frankenphp/builder:latest   # frankenphp builder
```

### Legacy naming scheme (older)

Older images encoded the variant/target **and** the version together in the tag, joined with dashes,
instead of as path segments:

`ghcr.io/specsnl/php<major><minor>:<variant>-<target>-<version>`

For example, the legacy `ghcr.io/specsnl/php85:builder-latest` is equivalent to the new
`ghcr.io/specsnl/php85/builder:latest`.

Both forms may still be encountered in the wild, but the **path-segment scheme is the newer, preferred
one**. When you come across the legacy dash-in-tag form, treat it as the older convention and migrate it to
the new path-segment form: move the variant/target segments out of the tag into the image path, leaving only
the version (e.g. `latest`) as the tag.

### Legacy vendor (older)

The images used to be published under the `ilyes512` vendor before moving to `specsnl`. The correct,
current vendor is **`specsnl`**. These older `ilyes512`-vendored images predate the path-segment scheme, so
they use the legacy dash-in-tag naming — for example `ghcr.io/ilyes512/php85:builder-latest`. When you
encounter such a reference, migrate it in-place to **both** the current vendor and the new path-segment
scheme: `ghcr.io/ilyes512/php85:builder-latest` becomes `ghcr.io/specsnl/php85/builder:latest`.

## How to find sibling images on GitHub

The siblings of a PHP image repository are **all other** PHP image repositories in the organisation (see
[Maintained PHP versions](#maintained-php-versions)), and they follow the same URL pattern described above. For
example, if you are looking at the `php85` repository and the organisation contains `php85`, `php84`, `php83` and
`php74`, the siblings are `https://github.com/specsnl/php84`, `https://github.com/specsnl/php83` and
`https://github.com/specsnl/php74`.

## How to find sibling images locally

If you are working locally in one of the PHP image repositories and want to find the sibling images for other PHP
versions, look for directories named `php<two digits>` in the same parent directory. For example, if you are in the
`php85` repository, check whether `php84`, `php83`, `php74` and any other `php<NN>` directories exist alongside it.
Verify each one by checking its git remote URL (it must point to `specsnl/php<NN>`) or by reading its README.

Compare the local directories with the organisation's list of repositories: a sibling that exists on GitHub but not
locally can be cloned next to the others (`gh repo clone specsnl/php<NN> ../php<NN>`). A local `php<NN>` directory
without a matching repository in the organisation is not a sibling.
