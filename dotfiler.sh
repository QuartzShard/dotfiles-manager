#!/bin/sh

# ==============================================================================
# DOTFILER
# ------------------------------------------------------------------------------
# A POSIX shell program to keep your dotfiles up to date in a repository.
# ------------------------------------------------------------------------------
# THIS PROGRAM IS LICENCED UNDER THE GNU GENERAL PUBLIC LICENCE V2.0. PLEASE
# READ THE LICENCE HERE: https://opensource.org/licenses/gpl-2.0.php
# ==============================================================================

Help () {
cat << EOF
Usage: dotfiler.sh [-h] [-c] (-[dipu])+ [system-tags]

Operational arguments:
  -h, --help     Print a complete help text and exit.
  -c, --conf_dir Change the working directory from $HOME/.dotfiler
  -d, --deploy   Deploys dotfiles to the system.
  -i, --install  Installs packages and configures the system.
  -p, --pull     Copies dotfiles into the repository.
  -u, --update   Updates the installed packages list.
  -x, --extra    Install dotfiles' extra dependencies.
EOF

[ "$1" = "full" ] && {
cat << EOF

System tags:
  System tags are optional arguments that MUST NOT start with the dash "-"
  character. They're used to specify a system to work with. Example systems are
  "laptop", "desktop", "shared-pc", "sister", "Groctel", etc.
  If no system was specified, the default system "" will be used.

Filelist file:
  Dotfiler needs a filelist file in ~/.dotfiler to keep track of the files in 
  your system. This file should be named "filelist" by default or "filelist-SYSTEM" for an
  specific system, e.g. "filelist-desktop".
  This file keeps track of your dotfiles using the following syntax:
  - Regular files: The path to the file from ~/.
  - Directories: The path to the file from ~/ terminated with "/*".
  For example, here are a regular file and a directory:
    .config/i3/config
    .local/share/fonts/*

Pkglist file:
  Dotfiler keeps tracks of your installed packages in a pkglist file in ~/.dotfiler 
  that follows the same naming conventions as the filelist file but does not need to
  be explicitly created by the user. To keep it simple, it only tracks the
  packages explicitly installed by the user.

Deplist file:
  You can store some commands to be run by Dotfiler in a deplist file in ~/.dotfiler
  that follows the same naming conventions as the filelist and pkglist files.
  Commands are parsed line by line and must not contain linefeeds. For example,
  these are two valid lines containing commands:
    curl -fLo \$HOME/.antigen.zsh git.io/antigen
    vim +"so \$HOME/.vimrc" +PlugInstall +qa\!

Argument order:
  Arguments are stored in a list of operations and a list of systems. Dotfiler
  will run all operations in the order they were passed in all systems in the
  order they were passed. For example, the following call:
    $ dotfiler.sh -p -u common laptop
  Will run the following tasks:
    - pull common
    - pull laptop
    - update common
    - update laptop

CAVEATS:
  This program only keeps track of your packages with "pacman" and "yay" on Arch
  or "apt" on Ubuntu. Pull request the project to add support other managers.

Licenced under the GNU General Public License v2.0:
https://opensource.org/licenses/gpl-2.0.php
https://github.com/Groctel/dotfiles-manager
EOF
}
}

# ==============================================================================
# CREATEFILELIST
# ------------------------------------------------------------------------------
# Prompts the user to create a filelist upon the absence of a filelist
# ==============================================================================

CreateFileList () {
	Confirm "yes" "Create a list of dotfiles to keep track of for $current_sys in $conf_dir" && {
		touch "$conf_dir/filelist$1"
		"${EDITOR:-vi}" "$conf_dir/filelist$1"	
	}
}

# ==============================================================================
# CONFIRM
# ------------------------------------------------------------------------------
# Prompts the user with a yes/no question. If priority for "yes" or "no" is
# specified, an empty string or any answer other than the not prioritised one
# will be interpreted as the prioritised one.
# ------------------------------------------------------------------------------
# ARGS:
# - $1 -> String : Either "yes" or "no" to set the answer priority or the
#                  question string if no priority is specified.
# - $2 -> String : The question string if priority is specified.
# ------------------------------------------------------------------------------
# RETURNS:
# EXIT_SUCCESS (0) is "yes" was answered and EXIT_FAILURE (1) otherwise, so that
# the function can be used with && and ||.
# ==============================================================================

Confirm () {
	answer=-1

	case "$1" in
	[Yy][Ee][Ss])
		printf "\033[1;32m:: \033[0m%s? \033[1;32m[Y/n]:\033[0m " "$2"
	;;
	[Nn][Oo])
		printf "\033[1;31m:: \033[0m%s? \033[1;31m[y/N]:\033[0m " "$2"
	;;
	*)
		printf "\033[1;33m:: \033[0m%s? \033[1;33m[y/n]:\033[0m " "$1"
	;;
	esac

	while [ $answer -eq -1 ]; do
		read -r yn

		case $yn in
		[Yy]*)
			answer=0
		;;
		[Nn]*)
			answer=1;
		;;
		*)
			case "$1" in
			[Yy][Ee][Ss])
				answer=0
			;;
			[Nn][Oo])
				answer=1
			;;
			esac
		;;
		esac
	done

	return $answer
}

# ==============================================================================
# ARRAY FUNCTIONS
# ------------------------------------------------------------------------------
# - FRONT: Reads the first item of a comma separated string array.
# - POP: Removes the first item from a comma separated string array.
# ------------------------------------------------------------------------------
# ARGS:
# - $1 -> String : The comma separated string array
# ------------------------------------------------------------------------------
# RETURNS:
# - FRONT: The first item of the array.
# - POP: The array with the first item removed.
# ==============================================================================

Front () {
	echo "$1" | sed 's/, */\n/g' | sed 'q;d'
}

Pop () {
	echo "$1" | sed 's/^,\?[^,]*,\? *//g'
}

# ==============================================================================
# COPYFILES
# ------------------------------------------------------------------------------
# Reads files from a text file and copies them in the root destination
# directory.
# ------------------------------------------------------------------------------
# ARGS:
# - $1 -> String : System files to be read and copied
# - $2 -> String : Source root firectory of files
# - $3 -> String : Destination root firectory of files
# - $4 -> String : Operation name to print on screen
# - $5 -> String : Optional overwrite string to rename destination files
# ==============================================================================

CopyFiles () {
	while read -r line; do
		printf "\033[1;32m -> \033[0m%s %s\n" "$4" "$line";
		cp -r "$2/"$line "$(Prepare "$line" "$3/" "$5")"
	done < "$conf_dir/filelist$1"
}

# ==============================================================================
# CHOOSE DISTRO
# ==============================================================================
# Gets the distro ID string from /etc/os-release and composes the distro
# specific function call with the distro name and the function prefix, then
# calls it. It basically holds the distro switches in one place with a kind of
# lambda function structure if you want to call it that.
# ------------------------------------------------------------------------------
# ARGS:
# - $1 -> String : Operation to compose the function call with
# - $2 -> String : The system tag
# ==============================================================================

ChooseDistro () {
	distro="$(grep "^ID=" /etc/os-release | sed 's/ID=//g')"

	case "$distro" in
	arch)
		operation="$1""Arch"
	;;
	ubuntu)
		operation="$1""Ubuntu"
	;;
	*)
		printf "\033[1;31mNo package manager configured for %s.\033[0m\n" \
	          "$distro"
	;;
	esac

	$operation "$2"
}

# ==============================================================================
# PREPARE
# ------------------------------------------------------------------------------
# Reads a line and creates a directory in the destination directory if required.
# ------------------------------------------------------------------------------
# ARGS:
# - $1 -> String : Line to be read
# - $2 -> String : Destination root directory of files
# - $3 -> String : Optional overwrite string to rename destination files
# ------------------------------------------------------------------------------
# RETURNS:
# The line's file name or parent directory name suffixed by the overwrite
# string, which might be empty.
# ==============================================================================

Prepare () {
	case "$1" in
	*/*)
		path="$(echo "$1" | sed -e 's/\(.\+\)\/.*$/\1/')""$3"
		mkdir -p "$2$path"
	;;
	*)
		path="$1$3"
	;;
	esac

	echo "$2$path"
}

# ==============================================================================
# DEPLOY FILES
# ------------------------------------------------------------------------------
# Reads the appropriate filelist file and deploys the specified files to the
# host's $HOME directory. If the user denies overwriting, it makes CopyFiles
# create ".new" files and directories instead.
# ------------------------------------------------------------------------------
# ARGS:
# - $1 -> String : The target system string
# ==============================================================================

Deploy () {
	overwrite=""
	sysname="$1"
	systag="-$1"

	[ "$1" = "DOTFILER-DEFAULT-SYSTEM" ] && {
		sysname="system"
		systag=""
	}

	Confirm "yes" "Deploy dotfiles from \"$sysname\" to system" && {
		Confirm "no" "Overwrite existing $sysname files" || overwrite=".new"

		printf "\033[1;35m==> \033[0;1mProcessing %s files\n" "$sysname"
		CopyFiles "$systag" "$conf_dir/files$systag" "$HOME" "Deploying" "$overwrite"
	}
}

# ==============================================================================
# INSTALL PACKAGES
# ------------------------------------------------------------------------------
# Reads the appropriate pkglist file and installs the specified packages in the
# host's system with their distro's manager. It allows the user to  review the
# packages they're going to install before doing do. Below this function are all
# distro subfunctions.
# ------------------------------------------------------------------------------
# ARGS (INSTALL):
# - $1 -> String : The target system string
# ------------------------------------------------------------------------------
# ARGS (INSTALL [DISTRO]):
# - $1 -> String : The system tag
# ==============================================================================

Install () {
	distro="$(grep "^ID=" /etc/os-release | sed 's/ID=//g')"
	sysname="$1"
	systag="-$1"

	[ "$1" = "DOTFILER-DEFAULT-SYSTEM" ] && {
		sysname="system"
		systag=""
	}

	Confirm "yes" "Review packages list (it will be permanently modified)" && {
		vi "$conf_dir/pkglist$systag" || (
			printf "\033[1;32m:: \033[0mSelect your editor: "
			read -r editor
			$editor "$conf_dir/pkglist$systag" || exit 1
		)
	}

	Confirm "no" "Proceed with the $sysname packages installation" &&
		ChooseDistro "Install" "$systag"
}

InstallArch () {
	if Confirm "yes" "Install with \"yay\" the AUR manager"; then
		git --version 1>/dev/null 2>&1 || sudo pacman --noconfirm -S git

		pacman -Q yay >/dev/null || {
			rm -rf yay 1>/dev/null 2>&1
			git clone https://aur.archlinux.org/yay.git
			cd yay && makepkg --noconfirm -si && cd ..
			rm -rf yay;
		}

		yay --noconfirm --answerclean All --answerdiff None --answeredit None \
		    --needed -S - < "$conf_dir/pkglist$1"
	else
		sudo pacman --noconfirm -S - < "$conf_dir/pkglist$1"
	fi
}

InstallUbuntu () {
	if Confirm "yes" "Install with \"apt\" package manager"; then
		git --version 1>/dev/null 2>&1 || sudo apt install git -y
		xargs sudo apt install -y < "$conf_dir/pkglist$1"
	fi
}

# ==============================================================================
# PULL FILES
# ------------------------------------------------------------------------------
# Reads the appropriate filelist file and pulls the specified files to the
# corresponding files directory.
# ------------------------------------------------------------------------------
# ARGS:
# - $1 -> String : The target system string
# ==============================================================================

Pull () {
	sysname="$1"
	systag="-$1"

	[ "$1" = "DOTFILER-DEFAULT-SYSTEM" ] && {
		sysname="system"
		systag=""
	}

	Confirm "yes" "Pull dotfiles from \"$sysname\" to repository" && {
		printf "\033[1;35m==> \033[0;1mProcessing \"%s\" files\n" "$sysname"

		rm -rf "files$systag" && mkdir "files$systag"
		CopyFiles "$systag" "$HOME" "$conf_dir/files$systag" "Pulling"
	}
}

# ==============================================================================
# UPDATE PACKAGES
# ------------------------------------------------------------------------------
# Updates the appropriate pkglist filewith the packages explicitly installed in
# the host's system using their distro's manager. Below this function are all
# distro subfunctions.
# ------------------------------------------------------------------------------
# ARGS (UPDATE):
# - $1 -> String : The target system string
# ------------------------------------------------------------------------------
# ARGS (UPDATE [DISTRO]):
# - $1 -> String : The system tag
# ==============================================================================

Update () {
	sysname="$1"
	systag="-$1"

	[ "$1" = "DOTFILER-DEFAULT-SYSTEM" ] && {
		sysname="system"
		systag=""
	}

	Confirm "yes" "Update \"$sysname\" package list" &&
		ChooseDistro "Update" "$systag"
}

UpdateArch () {
	yay -Qe | sed 's/ .*$//g' > "$conf_dir/pkglist$1"
}

UpdateUbuntu () {
	apt-mark showmanual | sort -u > "manlist"
	gzip -dc /var/log/installer/initial-status.gz \
		| sed -n 's/^Package: //p' \
		| sort -u > "initlist"
	comm -23 "manlist" "initlist" >"$conf_dir/pkglist$1"
	rm "manlist" "initlist"
}

# ==============================================================================
# EXTRA DEPENDENCIES
# ------------------------------------------------------------------------------
# Reads the appropriate deplist file and runs the specified commands to install
# the extra dependencies required by the system. It also resets the terminal
# emulators settings in case some of the operations messed with it, which can
# happen when calling Vim.
# ------------------------------------------------------------------------------
# ARGS:
# - $1 -> String : The target system string
# ==============================================================================

Extra () {
	old_stty_settings="$(stty -g)"

	sysname="$1"
	systag="-$1"

	[ "$1" = "DOTFILER-DEFAULT-SYSTEM" ] && {
		sysname="system"
		systag=""
	}

	printf "\033[1;35m==> \033[0;1mProcessing \"%s\" dependencies\n\033[0m" \
	       "$sysname"

	while read -r line; do
		sh -c "$line"
	done < "$conf_dir/deplist$systag"

	stty "$old_stty_settings" 1>/dev/null 2>&1
}

# ==============================================================================
# MAIN
# ------------------------------------------------------------------------------
# Handles the execution of the program based on the args provided to it. See the
# help text to learn about the arguments Dotfiler takes.
# ==============================================================================

operations=""
systems=""

[ $# -eq 0 ] && Help && exit 1
conf_dir="$HOME/.dotfiler" #Default conf_dir


while [ $# -gt 0 ]; do
	case "$1" in
		-c|--conf_dir)
			conf_dir=$2
			shift
		;;
		-d|--deploy)
			operations="$operations""deploy,"
		;;
		-h|--help)
			Help "full" && exit 0
		;;
		-i|--install)
			operations="$operations""install,"
		;;
		-p|--pull)
			operations="$operations""pull,"
		;;
		-u|--update)
			operations="$operations""update,"
		;;
		-x|--extra)
			operations="$operations""extra,"
		;;
		[!-]*)
			systems="$systems""$1,"
		;;
		*)
			Help && exit 1
		;;
	esac
	shift
done

[ "$systems" = "" ] && systems="DOTFILER-DEFAULT-SYSTEM"
[ -d $conf_dir ] || mkdir -p $conf_dir #Ensure conf_dir exists

while [ "$operations" != "" ]; do
	local_systems="$systems"

	current_op="$(Front "$operations")"
	operations="$(Pop "$operations")"

	while [ "$local_systems" != "" ]; do
		current_sys="$(Front "$local_systems")"
		local_systems="$(Pop "$local_systems")"
		current_systag="-$current_sys"
		( [ -f "$conf_dir/filelist$current_systag" ] ) 2>/dev/null || CreateFileList $current_systag #Prompt if missing config
		[ -d "$conf_dir/files$current_systag/" ] || mkdir -p "$conf_dir/files$current_systag" #Create files directory
		case "$current_op" in
			deploy)
				Deploy "$current_sys"
			;;
			install)
				Install "$current_sys"
			;;
			pull)
				Pull "$current_sys"
			;;
			update)
				Update "$current_sys"
			;;
			extra)
				Extra "$current_sys"
			;;
			*)
				printf "\033[1;31m==> Illegal operation \"%s\". Aborting...\033[0m\n" \
				       "$current_op"
				exit 1
		esac
	done
done

exit 0
