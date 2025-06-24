#!/bin/bash -l
set -euo pipefail

ROOT_USER=$(whoami)
chown -R "${ROOT_USER}:${ROOT_USER}" "$GITHUB_WORKSPACE"

HOST_URL="aur.archlinux.org"
REPO_URL="ssh://aur@${HOST_URL}/${INPUT_PACKAGE_NAME}.git"

act_group() {
	echo "::group::$1"
	shift
	"$@"
	echo "::endgroup::"
}

act_group_start() {
	echo "::group::$1"
}

act_group_end() {
	echo "::endgroup::"
}

get_version() {
	local version
	if [[ $GITHUB_REF_TYPE = "tag" ]]; then
		version=${GITHUB_REF##*\/}
	else
		echo "Attempting to resolve version from ref $GITHUB_REF"
		git -C "$GITHUB_WORKSPACE" fetch --tags --unshallow
		version=$(git -C "$GITHUB_WORKSPACE" describe --abbr=0 "$GITHUB_REF")
	fi >&2
	echo "$version"
}

get_goreleaser_assets() {
	local version="$1"
	local repo_name="$2"
	local clean_version=${version#v}
	
	# Common GoReleaser patterns
	echo "${repo_name}_${clean_version}_linux_amd64.tar.gz"
	echo "${repo_name}_${clean_version}_linux_arm64.tar.gz"
	echo "${repo_name}_${clean_version}_darwin_amd64.tar.gz"
	echo "${repo_name}_${clean_version}_darwin_arm64.tar.gz"
}

setup_ssh() {
	export SSH_PATH="$HOME/.ssh"
	# shellcheck disable=SC2174
	mkdir -p -m 700 "$SSH_PATH"
	ssh-keyscan -t ed25519 "$HOST_URL" >>"$SSH_PATH/known_hosts"
	echo -e "${INPUT_SSH_PRIVATE_KEY//_/\\n}" >"$SSH_PATH/aur.key"
	chmod 600 "$SSH_PATH/aur.key" "$SSH_PATH/known_hosts"
	cp /ssh_config "$SSH_PATH/config"
	chmod +r "$SSH_PATH/config"
	eval "$(ssh-agent -s)"
	ssh-add "$SSH_PATH/aur.key"
}

clone_aur_repo() {
	# shellcheck disable=SC2030
	(
		export GIT_SSH_COMMAND="ssh -i $SSH_PATH/aur.key -F $SSH_PATH/config -o UserKnownHostsFile=$SSH_PATH/known_hosts"
		git clone -v "$REPO_URL" "/tmp/aur-repo"
		chown -R builder:builder "/tmp/aur-repo"
	)
	cd "/tmp/aur-repo"
}

update_pkgbuild() {
	local pkgver_sed_escaped
	local repo_name=${GITHUB_REPOSITORY##*/}
	
	# Escape for sed
	pkgver_sed_escaped=$(printf '%s\n' "$PKGVER" | sed -e 's/[\/&]/\\&/g')
	
	# Update version and reset release number
	sed -i "s/pkgver=.*$/pkgver=$pkgver_sed_escaped/" PKGBUILD
	sed -i "s/pkgrel=.*$/pkgrel=1/" PKGBUILD
	
	# Remove all existing source and checksum lines
	sed -i '/^source.*=/d' PKGBUILD
	sed -i '/^source_x86_64.*=/d' PKGBUILD
	sed -i '/^source_aarch64.*=/d' PKGBUILD
	sed -i '/^sha256sums.*=/d' PKGBUILD
	sed -i '/^sha256sums_x86_64.*=/d' PKGBUILD
	sed -i '/^sha256sums_aarch64.*=/d' PKGBUILD
	
	# Update arch array to include both architectures
	sed -i "s/arch=.*/arch=('x86_64' 'aarch64')/" PKGBUILD
	
	# Add multi-arch sources after pkgrel line
	sed -i "/^pkgrel=/a source_x86_64=(\"https://github.com/${GITHUB_REPOSITORY}/releases/download/v\${pkgver}/${repo_name}_\${pkgver}_linux_amd64.tar.gz\")\nsource_aarch64=(\"https://github.com/${GITHUB_REPOSITORY}/releases/download/v\${pkgver}/${repo_name}_\${pkgver}_linux_arm64.tar.gz\")" PKGBUILD
	
	sudo -u builder updpkgsums
	sudo -u builder makepkg --printsrcinfo | sudo -u builder tee .SRCINFO
}

push_to_aur() {
	chown -R "$ROOT_USER:$ROOT_USER" .
	git config user.email "$INPUT_GIT_EMAIL"
	git config user.name "$INPUT_GIT_USERNAME"
	# shellcheck disable=SC2031
	(
		export GIT_SSH_COMMAND="ssh -i $SSH_PATH/aur.key -F $SSH_PATH/config -o UserKnownHostsFile=$SSH_PATH/known_hosts"
		git add PKGBUILD .SRCINFO
		if git diff-index --exit-code --quiet HEAD; then
			echo "::warning::No changes to PKGBUILD or .SRCINFO"
		else
			git commit -m "chore: bump version to $PKGVER"
			git push
			echo "::warning::Pushed to AUR"
		fi
	)
}

act_group_start "Version"
VERSION=$(get_version)
PKGVER=${VERSION#v}  # Remove 'v' prefix completely
echo "Version: $VERSION"
echo "Clean version: $PKGVER"
act_group_end

act_group 'Configure SSH' setup_ssh
act_group "Clone AUR repository @ $REPO_URL" clone_aur_repo
act_group "Update PKGBUILD for $INPUT_PACKAGE_NAME $PKGVER" update_pkgbuild
act_group "PKGBUILD" cat PKGBUILD
act_group "Push to AUR" push_to_aur
