# AUR Publish

Publish a package to the Arch User Repository (AUR) on GitHub release.

In total, this action will clone the AUR package repository, update the `PKGBUILD`/`.SRCINFO` and push to AUR.

## Inputs

| Name                | Description                                           | Default                              |
|---------------------|-------------------------------------------------------|--------------------------------------|
| \*`ssh-private-key` | The private SSH key to use to push the changes to AUR |                                      |
| `package-name`      | Name of the AUR package                               | `{{ github.event.repository.name }}` |
| `git-username`      | The username to use when creating the AUR repo commit | `AUR Release Action`                 |
| `git-email`         | The email to use when creating the AUR repo commit    | `github-action-bot@no-reply.com`     |

> \* **Required**

## Example

```yaml
name: AUR Publish

on:
  release:
    types: [published]

jobs:
  aur-publish:
    runs-on: ubuntu-latest
    environment: AUR
    steps:
      - uses: actions/checkout@v4
      - uses: varrcan/aur-publish-action@v1
        with:
          ssh_private_key: ${{ secrets.AUR_SSH_PRIVATE_KEY }}
          # the rest are optional
          package_name: my-aur-package
          git_username: me
          git_email: me@me.me
```
