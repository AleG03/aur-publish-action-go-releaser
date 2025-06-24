# AUR Publish

Publish a package to the Arch User Repository (AUR) on GitHub release.

In total, this action will clone the AUR package repository, update the `PKGBUILD`/`.SRCINFO` and push to AUR.

## GoReleaser Compatibility

This action is compatible with GoReleaser and automatically detects GoReleaser asset naming patterns (e.g., `project_1.0.0_linux_amd64.tar.gz`). It will update your PKGBUILD source URLs to match the actual release assets created by GoReleaser.

## Inputs

| Name                | Description                                           | Default                              |
|---------------------|-------------------------------------------------------|--------------------------------------|
| \*`ssh-private-key` | The private SSH key to use to push the changes to AUR |                                      |
| `package-name`      | Name of the AUR package                               | `{{ github.event.repository.name }}` |
| `git-username`      | The username to use when creating the AUR repo commit | `AUR Release Action`                 |
| `git-email`         | The email to use when creating the AUR repo commit    | `github-action-bot@no-reply.com`     |

> \* **Required**

## Example

### GoReleaser Integration

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  goreleaser:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-go@v4
        with:
          go-version: stable
      - uses: goreleaser/goreleaser-action@v5
        with:
          distribution: goreleaser
          version: latest
          args: release --clean
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  aur-publish:
    needs: goreleaser
    runs-on: ubuntu-latest
    environment: AUR
    steps:
      - uses: actions/checkout@v4
      - uses: AleG03/aur-publish-action-go-releaser@v1.2.0
        with:
          ssh_private_key: ${{ secrets.AUR_SSH_PRIVATE_KEY }}
          # the rest are optional
          package_name: my-aur-package
          git_username: me
          git_email: me@me.me
```
