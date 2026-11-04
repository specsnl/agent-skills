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

Each PHP image repository follows a consistent structure. The images come in up to three variants, each with its own
Dockerfile:

- `fpm/Dockerfile`: The Dockerfile for the FPM variant of the image.
- `apache/Dockerfile`: The Dockerfile for the Apache variant of the image.
- `frankenphp/Dockerfile`: The Dockerfile for the FrankenPHP variant of the image.

Not every repository ships every variant: a variant is only present when that PHP version supports it (e.g.
FrankenPHP requires PHP 8.2+, so `php74` has no `frankenphp` variant). Check which `<variant>/Dockerfile` files a
repository actually contains instead of assuming all three.

### The Dockerfiles are generated from a template

The variant Dockerfiles are **generated** — do not edit them by hand, except for their `FROM` image references:

- `Dockerfile.tmpl`: the single source for all variants (a [gomplate](https://docs.gomplate.ca/) template). All
  stages, `ARG`s (extension and tool versions), packages and `RUN` steps live here. Variant-specific parts are
  wrapped in conditionals such as `{{ if .is_frankenphp }}`.
- `variants/<variant>.yaml`: the template data per variant (e.g. `image_label`, `image_url`, `is_frankenphp`).
- `<variant>/Dockerfile`: the generated output. The external images of the `FROM` lines (`AS
  php_extension_installer`, `AS runtime`, `AS composer` and `AS node`) are the only values that are **not** in the
  template: the generator reads them back from the existing `<variant>/Dockerfile` and writes them into the new
  output. They are therefore changed by editing the `FROM` line in each `<variant>/Dockerfile` directly.
- `task generate` (in `Taskfile.dist.yml`) regenerates every `<variant>/Dockerfile` from the template, via the
  `hairyhenderson/gomplate` Docker image (pinned by `GOMPLATE_TAG_VERSION`).
- `scripts/pre-commit`: a git hook (installed with `task install:hooks`) that runs `task generate` and stages the
  Dockerfiles on every commit.
- The pull request workflow (`.github/workflows/pr.yml`) runs `task generate` and fails when the committed
  Dockerfiles differ from the output, so the template and the Dockerfiles must always be committed together and
  in sync.

So: to change anything other than a `FROM` image, edit `Dockerfile.tmpl` and run `task generate`. To change a `FROM`
image, edit it in every `<variant>/Dockerfile` (and run `task generate` to confirm the output is stable). Never rely
on the pre-commit hook alone — it is not installed in every clone, and a global `core.hooksPath` bypasses it.
`task install:hooks` copies the hook to `.git/hooks`, which fails in a `git worktree` (there `.git` is a file); don't
install it there, just run `task generate` yourself.

#### When `task generate` can't run

`task generate` needs Task and Docker. Resolve a missing tool in this order:

1. **Docker is missing, but a `gomplate` binary is installed** (ideally the version of `GOMPLATE_TAG_VERSION`): run
   the same generation without Docker, from the repository root:

    ```bash
    for f in */Dockerfile; do
        variant="${f%/Dockerfile}"
        export BASE_IMAGE="$(awk '/^FROM .* AS runtime$/ { print $2; exit }' "$f")"
        export PHP_EXTENSION_INSTALLER_IMAGE="$(awk '/^FROM .* AS php_extension_installer$/ { print $2; exit }' "$f")"
        export COMPOSER_IMAGE="$(awk '/^FROM .* AS composer$/ { print $2; exit }' "$f")"
        export NODE_IMAGE="$(awk '/^FROM .* AS node$/ { print $2; exit }' "$f")"
        gomplate --context ".=file://$PWD/variants/$variant.yaml" --file Dockerfile.tmpl > "$f.new" \
            && mv -f "$f.new" "$f"
    done
    ```

   The images are read before the output is written, and the output goes through a temporary file, because the
   generator reads the `FROM` images back from the same Dockerfile it overwrites. Record that the fallback was used.
2. **Task is missing, but Docker works:** run the `docker run ... hairyhenderson/gomplate` command of the
   `generate:variant` task in `Taskfile.dist.yml` for every variant, with the same environment variables as above.
3. **Neither works:** changes to `Dockerfile.tmpl` can't be made safely. Skip them and record it; `FROM`-only
   changes can still be committed, because they don't change the generated output.

When the pre-commit hook is installed and fails because of a missing tool, the commit fails with it. Don't bypass
it with `--no-verify`: resolve the tool as above, or skip that change and record it.

### Other files

- `files/general`: Contains files that are shared across all variants (copied into the image).
- `files/<variant_name>`: Contains files specific to the `<variant_name>` variant of the image.
- `Taskfile.dist.yml`: build, lint (Hadolint, pinned by `HADOLINT_TAG_VERSION`), generate, hook and shell tasks.
- `.github/workflows/`: `pr.yml` (template check and image builds), `main.yml` and `tag.yml` (publishing), all
  built on the reusable workflows of `specsnl/github-actions`.
- `.github/dependabot.yml`: daily Docker image (per variant directory) and GitHub Actions updates.

### Differences between the versions

The repositories are kept as similar as possible, but each PHP version may differ where it has to:

- **Variants**: older PHP versions lack variants they don't support (see above).
- **Debian release**: the base images use the newest Debian release available for that PHP version (e.g. `trixie`
  for PHP 8.3+, `bullseye` for PHP 7.4). Keep the Debian release of an existing tag when updating it.
- **Version-specific workarounds**: e.g. `php74` pins `ARG DEBIAN_SECURITY_SNAPSHOT` because Debian bullseye is
  end-of-life; its README explains why. Never remove such a workaround as a cleanup.
- **Extension and tool versions**: an `ARG` version can be lower in an older repository because newer releases
  dropped support for that PHP version (e.g. Xdebug 3.1.x is the last series supporting PHP 7.4).

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

The PHP image repositories are public, so no authentication is needed to list or clone them. Use the first source
that works, and record which one was used:

1. The `gh` CLI, as above.
2. A GitHub MCP repository search (`org:specsnl php in:name`), with the same name filter.
3. The public GitHub API without authentication:

    ```bash
    curl -fsSL 'https://api.github.com/orgs/specsnl/repos?type=public&per_page=100' \
        | jq -r '[.[] | select(.archived | not) | .name | select(test("^php[0-9]{2}$"))] | sort | reverse | .[]'
    ```

    Add `&page=2`, `&page=3`, … while a page returns 100 repositories.

4. The local sibling directories (see below). Record that the set may be incomplete.

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

### Verify a migrated reference

Before replacing a reference, check that the new image exists:
`docker buildx imagetools inspect <new-reference>` (or `docker manifest inspect`) exits non-zero when it doesn't.
When the new reference doesn't exist — e.g. an old release tag that was never published under the new scheme, or a
PHP version without a Specsnl repository — leave the old reference unchanged and record it. When the check can't run
(no Docker), migrate only `latest` and `main` references, which exist for every repository, and record the others
as unverified and unchanged.

### Legacy vendor (older)

The images used to be published under the `ilyes512` vendor before moving to `specsnl`. The correct,
current vendor is **`specsnl`**. These older `ilyes512`-vendored images predate the path-segment scheme, so
they use the legacy dash-in-tag naming — for example `ghcr.io/ilyes512/php85:builder-latest`. When you
encounter such a reference, migrate it in-place to **both** the current vendor and the new path-segment
scheme: `ghcr.io/ilyes512/php85:builder-latest` becomes `ghcr.io/specsnl/php85/builder:latest`. Verify the new
reference first, as described in [Verify a migrated reference](#verify-a-migrated-reference).

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
Verify each one by checking its git remote URL (it must point to `specsnl/php<NN>`) or by reading its README. A
remote that points to the old `ilyes512/php<NN>` repository is the same repository: it moved to `specsnl` and GitHub
redirects the old URL. Use it as-is, don't change the remote, and mention the outdated remote in the result.

Compare the local directories with the organisation's list of repositories: a sibling that exists on GitHub but not
locally can be cloned next to the others: `git clone https://github.com/specsnl/php<NN> ../php<NN>` (the
repositories are public, so this works without `gh`). When `../php<NN>` already exists but isn't that repository,
leave it untouched and clone to `../specsnl-php<NN>` instead. A local `php<NN>` directory without a matching
repository in the organisation is not a sibling.
