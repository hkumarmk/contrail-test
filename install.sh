#!/usr/bin/env bash

REQUIRED_PACKAGES="python-pip ant python-dev python-novaclient python-neutronclient python-cinderclient \
                    python-contrail patch python-heatclient python-ceilometerclient python-setuptools \
                    libxslt1-dev libz-dev libyaml-dev"

OPERATING_SYSTEM=''
ASKCONFIRMATION=1
USEVIRTUALENV="yes"

CONTRAIL_TEST_GIT_URL="https://github.com/juniper/contrail-test"
CONTRAIL_TEST_GIT_BRANCH="master"

# ansi colors for formatting heredoc
ESC=$(printf "\e")
GREEN="$ESC[0;32m"
NO_COLOR="$ESC[0;0m"
RED="$ESC[0;31m"

PYTHON2=$(which python || true)
PYTHON3=$(which python3 || true)
PYTHON=${PYTHON2:-$PYTHON3}


## Exit status codes (mostly following <sysexits.h>)
# successful exit
EX_OK=0

# wrong command-line invocation
EX_USAGE=64

# missing dependencies (e.g., no C compiler)
EX_UNAVAILABLE=69

# wrong python version
EX_SOFTWARE=70

# cannot create directory or file
EX_CANTCREAT=73

# user aborted operations
EX_TEMPFAIL=75

# misused as: unexpected error in some script we call
EX_PROTOCOL=76

# abort RC [MSG]
#
# Print error message MSG and abort shell execution with exit code RC.
# If MSG is not given, read it from STDIN.
#
abort () {
  local rc="$1"
  shift
  (echo -en "$RED$PROG: ERROR: $NO_COLOR";
      if [ $# -gt 0 ]; then echo "$@"; else cat; fi) 1>&2
  exit "$rc"
}

have_command () {
  type "$1" >/dev/null 2>/dev/null
}

# ask_yn PROMPT
#
# Ask a Yes/no question preceded by PROMPT.
# Set the env. variable REPLY to 'yes' or 'no'
# and return 0 or 1 depending on the users'
# answer.
#
ask_yn () {
    if [ $ASKCONFIRMATION -eq 0 ]; then
        # assume 'yes'
        REPLY='yes'
        return 0
    fi
    while true; do
        read -p "$1 [yN] " REPLY
        case "$REPLY" in
            [Yy]*)    REPLY='yes'; return 0 ;;
            [Nn]*|'') REPLY='no';  return 1 ;;
            *)        echo "Please type 'y' (yes) or 'n' (no)." ;;
        esac
    done
}

detect_os () {
    # instead of guessing which distribution this is, we check for the
    # package manager name as it basically identifies the distro
    if have_command dpkg; then
        OPERATING_SYSTEM='debian'
    elif have_command rpm; then
        OPERATING_SYSTEM='redhat'
    fi
}

apt_update () {
   apt-get update -y
}

running_as_root() {
  test "$(/usr/bin/id -u)" -eq 0
}

have_sw_package () {
    if [[ $OPERATING_SYSTEM = 'debian' ]]; then
        (dpkg -l "$1" | egrep -q ^i ) >/dev/null 2>/dev/null
    elif [[ $OPERATING_SYSTEM = 'redhat' ]]; then
        rpm -q "$1" >/dev/null 2>/dev/null
    fi
}


script_interrupted () {
    echo "Interrupted by the user. Cleaning up..."
    [ -n "${VIRTUAL_ENV}" -a "${VIRTUAL_ENV}" == "$VENVDIR" ] && deactivate

    case $CURRENT_ACTION in
        creating_venv|venv-created)
            if [ -d "$VENVDIR" ]
            then
                if ask_yn "Do you want to delete the virtual environment in '$VENVDIR'?"
                then
                    rm -rf "$VENVDIR"
                fi
            fi
            ;;
        downloading-src|src-downloaded)
            # This is only relevant when installing with --system,
            # otherwise the git repository is cloned into the
            # virtualenv directory
            if [ -d "$SOURCEDIR" ]
            then
                if ask_yn "Do you want to delete the downloaded source in '$SOURCEDIR'?"
                then
                    rm -rf "$SOURCEDIR"
                fi
            fi
            ;;
    esac

    abort $EX_TEMPFAIL "Script interrupted by the user"
}

trap script_interrupted SIGINT

which_missing_packages () {
    local missing=''
    for pkgname in "$@"; do
        if have_sw_package "$pkgname"; then
            continue;
        else
            missing="$missing $pkgname"
        fi
    done
    echo "$missing"
}

# Download command
download() {
    wget -nv $VERBOSE --no-check-certificate -O "$@";
}


install_required_sw () {
    local missing pkg_manager
    if [ $OPERATING_SYSTEM = 'debian' ]; then
        missing=$(which_missing_packages ${REQUIRED_PACKAGES})

        if [ "$ASKCONFIRMATION" -eq 0 ]; then
            pkg_manager="apt-get install --yes"
        else
            pkg_manager="apt-get install"
        fi
    else
        echo "contrail-support only support ubuntu/debian based systems at this moment"
        exit 1
    fi
    if ! have_command pip; then
        missing="$missing python-pip"
    fi

    if [ -n "$missing" ]; then
        cat <<__EOF__
The following software packages need to be installed
in order for contrail-test to work:$GREEN $missing
$NO_COLOR
__EOF__

        # If we are root
        if running_as_root; then
            cat <<__EOF__
In order to install the required software you would need to run as
'root' the following command:
$GREEN
    $pkg_manager $missing
$NO_COLOR
__EOF__
            # ask if we have to install it
            if ask_yn "Do you want me to install these packages for you?"; then
                # install
                if [[ "$missing" == *python-pip* ]]; then
                    missing=${missing//python-pip/}
                    if ! ${pkg_manager} python-pip; then
                        if ask_yn "Error installing python-pip. Install from external source?"; then
                            local pdir=$(mktemp -d)
                            local getpip="$pdir/get-pip.py"
                            download "$getpip" https://raw.github.com/pypa/pip/master/contrib/get-pip.py
                            if ! "$PYTHON" "$getpip"; then
                                abort $EX_PROTOCOL "Error while installing python-pip from external source."
                            fi
                        else
                            abort $EX_TEMPFAIL \
                                "Please install python-pip manually."
                        fi
                    fi
                fi
                if ! $pkg_manager $missing; then
                    abort $EX_UNAVAILABLE "Error while installing $missing"
                fi
                # installation successful
            else # don't want to install the packages
                die $EX_UNAVAILABLE "missing software prerequisites" <<__EOF__
Please, install the required software before installing contrail-test

__EOF__
            fi
        else # Not running as root
            cat <<__EOF__
There is a small chance that the required software
is actually installed though we failed to detect it,
so you may choose to proceed with contrail-test installation
anyway.  Be warned however, that continuing is very
likely to fail!

__EOF__
            if ask_yn "Proceed with installation anyway?"
            then
                echo "Proceeding with installation at your request... keep fingers crossed!"
            else
                die $EX_UNAVAILABLE "missing software prerequisites" <<__EOF__
Please ask your system administrator to install the missing packages,
or, if you have root access, you can do that by running the following
command from the 'root' account:
$GREEN
    $pkg_manager $missing
$NO_COLOR
__EOF__
            fi
        fi
    fi

}

##
# Setup contrail package repository
##
setup_contrail_packages () {
    if [[ -f $CONTRAIL_PACKAGES_DEB ]]; then
        dpkg -i $CONTRAIL_PACKAGES_DEB
        cd /opt/contrail/contrail_packages
        bash setup.sh
    else
        apt-get -y update
    fi

}

print_usage () {
    cat <<__EOF__
Usage: $PROG [options]

Install contrail-test.

Options:
$GREEN  -h, --help            $NO_COLOR Print this help text
$GREEN  -c, --contrail-deb    $NO_COLOR Path to Contrail-packages deb. If the path is available,
                              The package will be installed and setup local repo.
$GREEN  -y, --yes             $NO_COLOR Do not ask for confirmation: assume a 'yes' reply
                               to every question.
$GREEN  --no-color            $NO_COLOR Disable output coloring.
$GREEN  -u, --url             $NO_COLOR contrail-test git url.
$GREEN  -b, --branch          $NO_COLOR contrail-test git branch.
__EOF__
}

## STARTS HERE

short_opts='c:yhsu:b:'
long_opts='contrail-deb:,yes,no-color,help,system,url:,branch:'

set +e
if [ "x$(getopt -T)" = 'x' ]; then
    # GNU getopt
    args=$(getopt --name "$PROG" --shell sh -l "$long_opts" -o "$short_opts" -- "$@")
    if [ $? -ne 0 ]; then
        abort 1 "Type '$PROG --help' to get usage information."
    fi
    # use 'eval' to remove getopt quoting
    eval set -- "$args"
else
    # old-style getopt, use compatibility syntax
    args=$(getopt "$short_opts" "$@")
    if [ $? -ne 0 ]; then
        abort 1 "Type '$PROG -h' to get usage information."
    fi
    eval set -- "$args"
fi
set -e

# Command line parsing
while true
do
    case "$1" in
        -c|--contrail-deb)
            shift
            CONTRAIL_PACKAGES_DEB=$(readlink -m "$1")
            ;;
        -h|--help)
            print_usage
            exit $EX_OK
            ;;
        -s|--system)
            USEVIRTUALENV="no"
            ;;
        -y|--yes)
            ASKCONFIRMATION=0
            ;;
        --no-color)
            RED=""
            GREEN=""
            NO_COLOR=""
            ;;
        -u|--url)
            shift
            CONTRAIL_TEST_GIT_URL=$1
            ;;
        -b|--branch)
            shift
            CONTRAIL_TEST_GIT_BRANCH=$1
            ;;
        --)
            shift
            break
            ;;
        *)
            print_usage | die $EX_USAGE "An invalid option has been detected."
    esac
    shift
done


WORK_DIR=$(pwd)
detect_os
setup_contrail_packages
if ! [ -d "$WORK_DIR"/.git ]; then
    REQUIRED_PACKAGES="$REQUIRED_PACKAGES git"
fi

install_required_sw

cd ${WORK_DIR}
if ! [ -d "$WORK_DIR"/.git ]; then
    CURRENT_ACTION="downloading-src"
    git clone "$RALLY_GIT_URL" -b "$RALLY_GIT_BRANCH" "$SOURCEDIR"
    if ! [ -d $SOURCEDIR/.git ]; then
            abort $EX_CANTCREAT "Unable to download git repository"
    fi
    CURRENT_ACTION="src-downloaded"
fi

#pip install --upgrade -r requirements.txt