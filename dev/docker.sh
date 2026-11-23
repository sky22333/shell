#!/bin/sh
set -e

DEFAULT_CHANNEL_VALUE="stable"
if [ -z "$CHANNEL" ]; then
	CHANNEL=$DEFAULT_CHANNEL_VALUE
fi

DEFAULT_DOWNLOAD_URL="https://download.docker.com"
if [ -z "$DOWNLOAD_URL" ]; then
	DOWNLOAD_URL=$DEFAULT_DOWNLOAD_URL
fi

DEFAULT_REPO_FILE="docker-ce.repo"
if [ -z "$REPO_FILE" ]; then
	REPO_FILE="$DEFAULT_REPO_FILE"
fi

mirror=''
DRY_RUN=${DRY_RUN:-}
while [ $# -gt 0 ]; do
	case "$1" in
		--channel)
			CHANNEL="$2"
			shift
			;;
		--dry-run)
			DRY_RUN=1
			;;
		--mirror)
			mirror="$2"
			shift
			;;
		--*)
			echo "非法选项 $1"
			;;
	esac
	shift $(( $# > 0 ? 1 : 0 ))
done

case "$mirror" in
	aliyun)
		DOWNLOAD_URL="https://mirrors.aliyun.com/docker-ce"
		;;
	tuna)
		DOWNLOAD_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce"
		;;
	nju)
		DOWNLOAD_URL="https://mirror.nju.edu.cn/docker-ce"
		;;
	"")
		;;
	*)
		>&2 echo "未知镜像 '$mirror': 请使用 'aliyun'、'tuna' 或 'nju'"
		exit 1
		;;
esac

case "$CHANNEL" in
	stable)
		;;
	*)
		>&2 echo "未知 CHANNEL '$CHANNEL': 请使用 stable."
		exit 1
		;;
esac

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

is_dry_run() {
	if [ -z "$DRY_RUN" ]; then
		return 1
	else
		return 0
	fi
}

is_wsl() {
	case "$(uname -r)" in
	*microsoft* ) true ;;
	*Microsoft* ) true ;;
	* ) false;;
	esac
}

is_darwin() {
	case "$(uname -s)" in
	*darwin* ) true ;;
	*Darwin* ) true ;;
	* ) false;;
	esac
}

deprecation_notice() {
	distro=$1
	distro_version=$2
	echo "[弃用] $distro $distro_version 已停止支持，建议升级。"
	sleep 3
}

get_distribution() {
	lsb_dist=""
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	echo "$lsb_dist"
}

get_codename() {
	if [ -r /etc/os-release ]; then
		. /etc/os-release
		echo "$VERSION_CODENAME"
	fi
}

echo_docker_as_nonroot() {
	if is_dry_run; then
		return
	fi
	if command_exists docker && [ -e /var/run/docker.sock ]; then
		(
			set -x
			$sh_c 'docker --version'
		) || true
	fi

	echo "Docker 安装完成。"
}

do_install() {
	echo "开始 Docker 安装"

	if command_exists docker; then
		echo "警告：已存在 docker 命令，5秒后继续。可按 Ctrl+C 取消。"
		sleep 5
	fi

	user="$(id -un 2>/dev/null || true)"

	sh_c='sh -c'
	if [ "$user" != 'root' ]; then
		if command_exists sudo; then
			sh_c='sudo -E sh -c'
		elif command_exists su; then
			sh_c='su -c'
		else
			cat >&2 <<-'EOF'
			错误：此安装程序需要以 root 权限运行命令。
			我们无法找到 "sudo" 或 "su" 来执行此操作。
			EOF
			exit 1
		fi
	fi

	if is_dry_run; then
		sh_c="echo"
	fi

	lsb_dist=$( get_distribution )
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

	if is_wsl; then
		echo "检测到 WSL，建议使用 Docker Desktop for Windows"
		sleep 3
	fi

	case "$lsb_dist" in

		ubuntu)
			dist_version="$(get_codename)"
			if [ -z "$dist_version" ] && command_exists lsb_release; then
				dist_version="$(lsb_release -cs)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
		;;

		debian|raspbian)
			dist_version="$(get_codename)"
		;;

		rhel|rocky)
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --release | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

	esac

	if [ "$lsb_dist" = "rocky" ] && [ "$DOWNLOAD_URL" != "$DEFAULT_DOWNLOAD_URL" ]; then
		if ! curl -fsS -m 10 -o /dev/null "$DOWNLOAD_URL/linux/rocky/$REPO_FILE"; then
			echo "信息：镜像源未提供 Rocky 仓库，已改用官方源。"
			DOWNLOAD_URL="$DEFAULT_DOWNLOAD_URL"
		fi
	fi

	case "$lsb_dist.$dist_version" in
		rhel.7)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		debian.buster|debian.stretch|debian.jessie)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		raspbian.buster|raspbian.stretch|raspbian.jessie)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		ubuntu.bionic|ubuntu.xenial|ubuntu.trusty)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		ubuntu.mantic|ubuntu.lunar|ubuntu.kinetic|ubuntu.impish|ubuntu.hirsute|ubuntu.groovy|ubuntu.eoan|ubuntu.disco|ubuntu.cosmic)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		fedora.*)
			if [ "$dist_version" -lt 40 ]; then
				deprecation_notice "$lsb_dist" "$dist_version"
			fi
			;;
	esac

	case "$lsb_dist" in
		ubuntu|debian|raspbian)
			if [ -z "$dist_version" ]; then
				>&2 echo "错误：无法确定 $lsb_dist 的版本代号。"
				exit 1
			fi
			pre_reqs="ca-certificates curl"
			apt_repo="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $DOWNLOAD_URL/linux/$lsb_dist $dist_version $CHANNEL"
			(
				if ! is_dry_run; then
					set -x
				fi
				$sh_c 'apt-get -qq update >/dev/null'
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get -y -qq install $pre_reqs >/dev/null"
				$sh_c 'install -m 0755 -d /etc/apt/keyrings'
				$sh_c "curl -fsSL \"$DOWNLOAD_URL/linux/$lsb_dist/gpg\" -o /etc/apt/keyrings/docker.asc"
				$sh_c "chmod a+r /etc/apt/keyrings/docker.asc"
				if [ ! -d /etc/apt/sources.list.d ]; then
					$sh_c 'mkdir -p /etc/apt/sources.list.d'
				fi
				$sh_c "echo \"$apt_repo\" > /etc/apt/sources.list.d/docker.list"
				$sh_c 'apt-get -qq update >/dev/null'
			)
			(
				pkgs="docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras docker-buildx-plugin"
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get -y -qq install $pkgs >/dev/null"
			)
			echo_docker_as_nonroot
			exit 0
			;;
		fedora|rhel|rocky)
			repo_file_url="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE"
			(
				if ! is_dry_run; then
					set -x
				fi
				if command_exists dnf5; then
					$sh_c "dnf -y -q --setopt=install_weak_deps=False install dnf-plugins-core"
					$sh_c "dnf5 config-manager addrepo --overwrite --save-filename=docker-ce.repo --from-repofile='$repo_file_url'"
					$sh_c "dnf makecache"
				elif command_exists dnf; then
					$sh_c "dnf -y -q --setopt=install_weak_deps=False install dnf-plugins-core"
					$sh_c "rm -f /etc/yum.repos.d/docker-ce.repo  /etc/yum.repos.d/docker-ce-staging.repo"
					$sh_c "dnf config-manager --add-repo $repo_file_url"
					$sh_c "dnf makecache"
				else
					$sh_c "yum -y -q install yum-utils"
					$sh_c "rm -f /etc/yum.repos.d/docker-ce.repo  /etc/yum.repos.d/docker-ce-staging.repo"
					$sh_c "yum-config-manager --add-repo $repo_file_url"
					$sh_c "yum makecache"
				fi
			)
			if command_exists dnf; then
				pkg_manager="dnf"
				pkg_manager_flags="-y -q --best"
			else
				pkg_manager="yum"
				pkg_manager_flags="-y -q"
			fi
			(
				pkgs="docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras docker-buildx-plugin"
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "$pkg_manager $pkg_manager_flags install $pkgs"
			)
			echo_docker_as_nonroot
			exit 0
			;;
		*)
			if [ -z "$lsb_dist" ]; then
				if is_darwin; then
			echo "错误：不支持 macOS，请用 Docker Desktop。"
			exit 1
				fi
			fi
			echo "错误：不支持的发行版 $lsb_dist。"
			exit 1
			;;
	esac
	exit 1
}

do_install
