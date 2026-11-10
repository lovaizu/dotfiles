#!/bin/sh

# -e: exit on error
# -u: exit on unset variables
set -eu

# The directory of this script, found in a way that any sh supports:
# https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

# mise installs the other tools, so this script installs mise itself, from
# its GitHub release. Each sum is that of the binary for the platform, as
# the release's SHASUMS256.txt gives it. To change the version, take the
# new sums from that file.
mise_version=2026.11.5
bin_dir="${HOME}/.local/bin"
mise="${bin_dir}/mise"
if [ "$("$mise" --version 2>/dev/null | cut -d ' ' -f 1)" != "$mise_version" ]; then
	case "$(uname -s)-$(uname -m)" in
	Linux-x86_64) platform=linux-x64 sum=7a5b051d6f17d335c502f8047a5175cf3103f347d91942771c60da4e302ebcb0 ;;
	Linux-aarch64 | Linux-arm64) platform=linux-arm64 sum=3cb907fc1d3f033afab40b4a8efca4fd71440bf91b63bfca3beb3302b0f3a6d5 ;;
	Darwin-arm64) platform=macos-arm64 sum=4f9faebcfac7f8bb1321e697ba7a5ba26f645233aa269741a16482f757bd482e ;;
	Darwin-x86_64) platform=macos-x64 sum=f9489962f8c979520111b86b70c5da91086c54c9141edd116198d89093784a1e ;;
	*)
		echo "setup.sh: mise has no binary for $(uname -s) on $(uname -m), so setup.sh can't install it." >&2
		exit 1
		;;
	esac
	echo "Installing mise ${mise_version} to '${mise}'" >&2
	mkdir -p "${bin_dir}"
	part="${mise}.part"
	if ! curl -fsSL -o "${part}" "https://github.com/jdx/mise/releases/download/v${mise_version}/mise-v${mise_version}-${platform}"; then
		rm -f "${part}"
		echo "setup.sh: the download of mise failed. curl said why in the preceding output." >&2
		exit 1
	fi
	if command -v sha256sum >/dev/null; then
		got="$(sha256sum "${part}" | cut -d ' ' -f 1)"
	else
		# macOS has no sha256sum.
		got="$(shasum -a 256 "${part}" | cut -d ' ' -f 1)"
	fi
	if [ "${got}" != "${sum}" ]; then
		rm -f "${part}"
		echo "setup.sh: the download of mise has sha256 ${got}, not ${sum}, so setup.sh didn't install it." >&2
		exit 1
	fi
	chmod +x "${part}"
	mv "${part}" "${mise}"
fi

# chezmoi places the global config of mise only when it runs, so mise reads
# the config from this clone to install chezmoi. --locked installs only the
# version and sha256 that the mise.lock beside the config keeps.
config="${script_dir}/home/private_dot_config/mise/config.toml"
MISE_GLOBAL_CONFIG_FILE="${config}" "$mise" install --locked chezmoi
chezmoi="$(MISE_GLOBAL_CONFIG_FILE="${config}" "$mise" which chezmoi)"

# The scripts that chezmoi runs find mise, and the tools that it installs,
# on PATH, whatever the PATH of this shell is.
PATH="${bin_dir}:${PATH}"
. "${script_dir}/home/private_dot_config/shell/mise.sh"
export PATH

set -- init --apply --keep-going --source="${script_dir}"

echo "Running 'chezmoi $*'" >&2
# exec: replace current process with chezmoi
exec "$chezmoi" "$@"
