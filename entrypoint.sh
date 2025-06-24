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
	local clean_version=${PKGVER#v}
	
	# Escape for sed
	pkgver_sed_escaped=$(printf '%s\n' "$PKGVER" | sed -e 's/[\/&]/\\&/g')
	
	# Update version and reset release number
	sed -i "s/pkgver=.*$/pkgver=$pkgver_sed_escaped/" PKGBUILD
	sed -i "s/pkgrel=.*$/pkgrel=1/" PKGBUILD
	
	# Update source URLs to match GoReleaser naming convention
	if grep -q "source.*=.*\${pkgname}" PKGBUILD; then
		# Replace source URLs with GoReleaser pattern
		sed -i "s|source.*=.*|source=(\"https://github.com/${GITHUB_REPOSITORY}/releases/download/v\${pkgver}/${repo_name}_\${pkgver}_linux_amd64.tar.gz\")|" PKGBUILD
	elif grep -q "source_x86_64.*=" PKGBUILD; then
		# Handle architecture-specific sources
		sed -i "s|source_x86_64.*=.*|source_x86_64=(\"https://github.com/${GITHUB_REPOSITORY}/releases/download/v\${pkgver}/${repo_name}_\${pkgver}_linux_amd64.tar.gz\")|" PKGBUILD
		sed -i "s|source_aarch64.*=.*|source_aarch64=(\"https://github.com/${GITHUB_REPOSITORY}/releases/download/v\${pkgver}/${repo_name}_\${pkgver}_linux_arm64.tar.gz\")|" PKGBUILD
	fi
	
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
PKGVER=${VERSION##*/v}
echo "Version: $VERSION"
act_group_end

act_group 'Configure SSH' setup_ssh
act_group "Clone AUR repository @ $REPO_URL" clone_aur_repo
act_group "Update PKGBUILD for $INPUT_PACKAGE_NAME $PKGVER" update_pkgbuild
act_group "PKGBUILD" cat PKGBUILD
act_group "Push to AUR" push_to_aur
