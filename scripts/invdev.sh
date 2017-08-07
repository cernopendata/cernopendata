#!/bin/sh
#
# This file is part of CERN Open Data Portal.
# Copyright (C) 2017 CERN.
#
# CERN Open Data Portal is free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# CERN Open Data Portal is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with CERN Open Data Portal; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA 02111-1307, USA.
#
# In applying this license, CERN does not
# waive the privileges and immunities granted to it by virtue of its status
# as an Intergovernmental Organization or submit itself to any jurisdiction.

# TODO:
#   * Add Flask-IPython, Flask-debugtoolbar, ipdb, etc. support
#     with or without using flags (e.g. --debugtoolbar)
#   * Add support to pip install packages from devmodules-folder
#     to other containers other than 'web'

# TODO: If script is executed from modulefolder, install this module to devenv.
# TODO: Give path to modulefolder as parameter, install the module to devenv.
# TODO: Give git or http URL in pip requirements file notation to module
#       as a parameter, download given module, install the module to devenv.



script_dir=$(cd -P -- "$(dirname -- "$0")" && pwd -P)

# Name of the main executable of Invenio3 instance.
invinstance=${INVENIO_WEB_INSTANCE:-cernopendata}

# Name of the main executable of Invenio3 instance.
invinstance_short=cod

# Name or full path of the Docker Compose file that
# defines the development environment
dcofile=${INVENIO_DEVENV_DCOFILE:-$script_dir/../docker-compose-dev.yml}

# Path to file which contains a list of git-repository URLs to fetch
# (e.g "./devmodules.lst")
input_file="./devmodules.lst"

# Path to folder on host system where development modules should be downloaded.
# Path must be relative to directory where this script is located.
# Make sure that this folder is mounted from host to at least 'web'
# and 'worker' containers to path defined in 'container_devmodules_folder'.
# (e.g "$script_dir/../../devmodules")
local_devmodules_folder="$script_dir/../devmodules"

# Absolute path to 'devmodules' -folder inside the containers.
# Make sure that 'local_devmodules_folder' is mounted to this folder
# for at least in 'web' and 'worker' containers.
# (e.g "/devmodules")
container_devmodules_folder="/devmodules"

# Name of the pip requirement -file which will be generated by this script.
# (e.g "requirements-extra.txt")
requirements_file="requirements-extra.txt"

# quit on errors and unbound symbols:
#set -o errexit
#set -o nounset

# runs as root or needs sudo?
#if [ $(id -u) -ne 0 ]; then
#	sudo='sudo'
#else
#    sudo=''
#fi


check_for_git () {
  # Check that git-executable is found
  # From: https://stackoverflow.com/a/677212
  command -v git >/dev/null 2>&1 ||
    { echo >&2 "Git executable is required but ";
      echo >&2 "not installed.  Canceling.";
      exit 1; }
}


check_for_docker_compose () {
  # Check that docker-compose -executable is found
  # From: https://stackoverflow.com/a/677212
  command -v docker-compose >/dev/null 2>&1 ||
    { echo >&2 "Docker Compose executable is required but ";
      echo >&2 "not installed.  Canceling.";
      exit 1; }
}


aliases () {
  # FIXME: Write function description
  # Remember to add semicolon to your commands when eval:ing them with $()
  # https://stackoverflow.com/a/16619261
#  echo "alias dcoew='docker-compose exec web';"
#  echo "alias dco='docker-compose';"
#  echo "alias \"invd\"='$script_dir/invdev.sh $invinstance';"
#  echo "alias \"${invinstance_short}dev\"='$script_dir/invdev.sh $invinstance';"

  echo 'function dco { docker-compose "$@"; };'
  echo 'function dcoe { docker-compose exec "$@"; };'
  echo 'function dcoew { docker-compose exec web "$@"; };'
  echo "function invd { $script_dir/invdev.sh $invinstance \"\$@\"; };"
  echo "function ${invinstance_short}dev { $script_dir/invdev.sh $invinstance \"\$@\"; };"

}

coddev() {
  # FIXME: Write function description

  check_for_docker_compose

  dco='docker-compose'
  dcoew='docker-compose exec web'

  if [ "$2" != "" ]
  then
    case $2 in
      assets)       echo "Executing:"
                    echo "  docker-compose exec web bash -c \"cernopendata collect -v\""
                    echo "  docker-compose exec web bash -c \"cernopendata assets build\""
                    ${dcoew} bash -c "
                        cernopendata collect -v &&
                        cernopendata assets build
                       "
                    ;;
      reqs)         generate_requirements_txt
                    ;;
      requirements) generate_requirements_txt
                    ;;
      download)     parse_and_download_modulelist
                    ;;
      init)         init
                    ;;
      install)      install_modules
                    ;;
      logs)         echo "Executing:"
                    echo "  docker-compose -f $dcofile logs --follow --timestamps --tail=100"
                    ${dco} -f "$dcofile" logs -f -t --tail=100
                    ;;
      reset-index)  ${dcoew} bash -c "
                        echo \"Executing: cernopendata db destroy\" &&
                        cernopendata db destroy &&
                        echo \"Executing: curl -XDELETE \"elasticsearch:9200/_all\"\" &&
                        curl -XDELETE \"elasticsearch:9200/_all\"
                       "
                    coddev - initdb
                    ;;
      initdb)       ${dcoew} bash -c "
                        echo \"Executing: cernopendata db init\" &&
                        cernopendata db init &&
                        echo \"Executing: cernopendata db create\" &&
                        cernopendata db create &&
                        echo \"Executing: cernopendata index init\" &&
                        cernopendata index init &&
                        echo \"Executing: cernopendata fixtures collections\" &&
                        cernopendata fixtures collections &&
                        echo \"Executing: cernopendata fixtures records\" &&
                        cernopendata fixtures records &&
                        echo \"Executing: cernopendata fixtures pids\" &&
                        cernopendata fixtures pids &&
                        echo \"Executing: cernopendata fixtures terms\" &&
                        cernopendata fixtures terms
                       "
                    coddev - reindex
                    ;;
      reindex)      ${dcoew} bash -c "
                        echo \"Executing: cernopendata index queue init\" &&
                        cernopendata index queue init &&
                        echo \"Executing: cernopendata index reindex -t termid --yes-i-know\" &&
                        cernopendata index reindex -t termid --yes-i-know &&
                        echo \"Executing: cernopendata index reindex -t recid --yes-i-know\" &&
                        cernopendata index reindex -t recid --yes-i-know &&
                        echo \"Executing: cernopendata index run\" &&
                        cernopendata index run
                       " # Index recid last because of exception it throws in the end?
                    ;;
      restart)      echo "Executing:"
                    echo "  docker-compose stop --timeout 5 web worker nginx"
                    echo "  docker-compose start web worker nginx"
                    ${dco} stop --timeout 5 web worker nginx
                    ${dco} start web worker nginx
                    ;;
      up)           echo "Executing:"
                    echo "  docker-compose -f $dcofile up -d"
                    ${dco} -f "$dcofile" up -d
                    ;;
      down)         echo "Executing:"
                    echo "  docker-compose -f $dcofile down"
                    ${dco} -f "$dcofile" down
                    ;;
      ps)           echo "Executing:"
                    echo "  docker-compose -f $dcofile ps"
                    ${dco} -f "$dcofile" ps
                    ;;
      status)       echo "Executing:"
                    echo "  docker-compose -f $dcofile ps"
                    ${dco} -f "$dcofile" ps
                    ;;
      build)        echo "Executing:"
                    echo "  docker-compose -f $dcofile build"
                    ${dco} -f "$dcofile" build
                    ;;

    esac
  else
    # FIXME: Order alphabetically
    # FIXME: Refactor to a function in order to have 'help' and '-h' working
    echo "Helpers for various actions for development environment."
    echo ""
    echo "Common Invenio commands:"
    echo "  init                 # FIXME: Write instructions"
    echo "  install              # FIXME: Write instructions"
    echo "  restart              # FIXME: Write instructions"
    echo "  up                   # FIXME: Write instructions"
    echo "  down                 # FIXME: Write instructions"
    echo "  ps                   # FIXME: Write instructions"
    echo "  status               # FIXME: Write instructions"
    echo "  build                # FIXME: Write instructions"
    echo "  reqs, requirements   # FIXME: Write instructions"
    echo "  install              # FIXME: Write instructions"
    echo "  download             # FIXME: Write instructions"
    echo ""
    echo "CERN Open Data specific commands:"
    echo "  assets               # FIXME: Write instructions"
    echo "  initdb               # FIXME: Write instructions"
    echo "  reindex              # FIXME: Write instructions"
    echo "  reset-index          # FIXME: Write instructions"
  fi

}


generate_license () {
  echo "# -*- coding: utf-8 -*-"
  echo "#"
  echo "# This file is part of CERN Open Data Portal."
  echo "# Copyright (C) 2017 CERN."
  echo "#"
  echo "# CERN Open Data Portal is free software; you can redistribute it"
  echo "# and/or modify it under the terms of the GNU General Public License as"
  echo "# published by the Free Software Foundation; either version 2 of the"
  echo "# License, or (at your option) any later version."
  echo "#"
  echo "# CERN Open Data Portal is distributed in the hope that it will be"
  echo "# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of"
  echo "# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU"
  echo "# General Public License for more details."
  echo "#"
  echo "# You should have received a copy of the GNU General Public License"
  echo "# along with CERN Open Data Portal; if not, write to the"
  echo "# Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,"
  echo "# MA 02111-1307, USA."
  echo "#"
  echo "# In applying this license, CERN does not"
  echo "# waive the privileges and immunities granted to it by virtue of its status"
  echo "# as an Intergovernmental Organization or submit itself to any jurisdiction."
  echo ""
}


generate_requirements_txt () {
  # FIXME: Write function description

  # FIXME: Ask confirmation to overwrite old file.

  # TODO: Take folder/path to parse as a parameter

  modulelist=$* # Intentionally left without quoting.
  content=""
  file="$local_devmodules_folder/$requirements_file"

  echo ""
  echo "Generating requirements-extra.txt with new modules..."
  echo ""

  if [ -s "$file" ]; then
    content=$(grep -E '^(#)' "$file")
  else
    content=$(generate_license)
  fi

  echo "$content" > "$file"


  # TODO: Add options to include Flask-IPython, Flask-Debugtoolbar, ipdb, etc.

  #flag_flask_ipython=$(echo "$@" | grep -oe "--\<flask_ipython\>")
  #flag_flask_debugtoolbar=$(echo "$@" | grep -oe "--\<debugtoolbar\>")
  #flag_flask_debugtoolbar=$(echo "$@" | grep -oe "--\<ipdb\>")


  # NOTE: Use only one of the following methods to populate requirements.txt

  # Loop trough the devmodules-list received as a parameter
  # and mark each entry to be an installable package.
#  for entry in ${modulelist}
#  do
#    # Select only text after final '/' -character
#    entry=$(echo "$entry" | sed 's#.*/##')
#    # Select only text before final '.' -character
#    entry=$(echo "$entry" | sed 's/\.[^.]*$//')
#    echo "-e file:///${container_devmodules_folder##*/}/${entry##*/}#egg=${entry##*/}" >> "$file"
#  done

#  # Loop trough the local devmodules directory and mark each subdirectory
#  # to be an installable package.
  for entry in "$local_devmodules_folder"/*
  do
    if echo "$entry" | grep -qve "$requirements_file"; then
      echo "-e file:///${container_devmodules_folder##*/}/${entry##*/}#egg=${entry##*/}" >> "$file"
    fi
  done

  echo "Done"
  echo ""

}


parse_and_download_modulelist () {
  # FIXME: Write function description

  check_for_git

  repolist=""

  # Read in repolist entries from file.
  # From: https://stackoverflow.com/a/24537755
  echo "Searching for development modules in $input_file ..."
  echo ""
  repolist=$(grep -vE '^(\s*$|#)' "$input_file" | sort | uniq)

  if [ "$repolist" = "" ]; then
    echo "No development modules defined in $input_file"
    echo ""
  else
    echo "Adding modules:"
    echo ""
    echo "$repolist"
    echo ""
  fi


  # Read in repolist entries from envvar if it exists.
  repolist_envvar=${COD_DEVMODULES-""}
  if [ "$repolist_envvar" != "" ]; then
    # TODO: Append URLs to repolist
    echo "Searching for development modules in \$COD_DEVMODULES"
    echo ""
    echo "Adding modules:"
    echo ""
    echo "..."
    echo ""

  else
    echo "No development modules defined in \$COD_DEVMODULES"
    echo ""
  fi


  # Remove duplicates from the repolist
  #repolist=$(echo "$repolist" | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
  #repolist=$(echo "$repolist" | tr ' ' '\n' | sort | uniq)
  repolist=$(echo "$repolist" | sort | uniq)


  if [ "$repolist" != "" ]; then
    # Present a list of modules to be downloaded
    # Ask for confirmation
    echo "Following modules will be downloaded:"
    echo ""
    echo "$repolist"
    echo ""
    echo "Continue downloading?"
    echo "(Y)es or (n)o: "

    read confirmdownload

    if [ "$confirmdownload" = "Y" ]; then

      echo ""

      # FIXME: Refactor downloading part into a separate function
      #        Give $repolist as a parameter.

      # Check if Devmodules-folder exists.
      # Ask for confirmation to overwrite (delete).
      # Otherwise exit
      if [ -d "$local_devmodules_folder" ]; then
        echo "Devmodules-folder already exists in:"
        echo $(cd ${local_devmodules_folder}; pwd)
        echo ""
        echo "Script will DELETE contents of Devmodules-folder!"
        echo "Any uncommitted changes will be lost!"
        echo ""
        echo "Are you sure you want to continue?"
        echo "(Y)es or (n)o: "

        read confirmdelete

        if [ "$confirmdelete" = "Y" ]; then
          echo ""
          echo "Deleting contents of Devmodules-folder..."
          echo ""
          rm -rf "$local_devmodules_folder"
          mkdir "$local_devmodules_folder"
          echo "Deleted"
          echo ""
        else
          echo ""
          echo "Cancelled"
          echo ""
          exit 1
        fi
      else
        mkdir "$local_devmodules_folder"
      fi

      echo ""
      echo "Downloading modules to Devmodules-folder..."
      echo ""

      # Run in a subshell to preserve IFS of current shell
      # Also had some troubles getting '\n' to work properly without subshell.
      # https://stackoverflow.com/a/19192656
      (
        # Change to _devmodules folder and try to clone each entry of repolist.
        cd "$local_devmodules_folder"

        IFS="$(echo '\n\b')"
        # echo -n "$IFS" | od -t x1 # Handy debug to printout IFS as octal
        for j in ${repolist}; do
          echo "Found $j"
          eval $(echo "git clone ${j}") #NOTE eval and globbing!
        done
      )

      echo ""
      echo "Done"
      echo ""

    else
      echo ""
      echo "Cancelled"
      echo ""
      exit 1
    fi
  else
    echo ""
    echo "No development modules defined."
    echo "List development modules in '$input_file'"
    echo "file or in '\$COD_DEVMODULES' environment variable"
    echo ""
  fi

}


init() {
  parse_and_download_modulelist
  # FIXME: Is exit 0 in previous preventing this from running?
  generate_requirements_txt
}


install_modules () {
  # FIXME: Write function description
  check_for_docker_compose

  # Check that web-container is running
  docker-compose exec web echo "Available!"

  # FIXME: Check that devmodules folder exists in host.
  if [ -d "$local_devmodules_folder" ]; then
    echo "Folder exists!"
  fi

  # FIXME: Check that requirements-extra.txt exists in host.
  if [ -s "$local_devmodules_folder/$requirements_file" ]; then
    echo "Requirements file exists!"
  fi

  # FIXME: Check that requirements -file exists in container
  # This check is needed because if you have started the container before
  # generating the requirements -file, the generated requirements-file
  # doesn't necessarily show up inside the container without stopping and
  # starting the container first.
  if [ $(docker-compose exec web test -f "$container_devmodules_folder/$requirements_file") ]; then
    echo "Requirements file exists inside container!"
  fi

  # (Re)install packages under development
  echo "Installing development modules to web-container"
  docker-compose exec web bash -c "pip install -r $container_devmodules_folder/$requirements_file"
  echo "Installing development modules to worker-container"
  docker-compose exec worker bash -c "pip install -r $container_devmodules_folder/$requirements_file"
}


usage () {
  # FIXME: Better instructions
  echo "# ${0##*/} Setups a development environment"
  echo ""
  echo "# Usage:"
  echo "#  init                 Initializes a development environment."
  echo "#  install              Installs development modules to container."
  echo "#  $invinstance         Invenio development shortcuts."
  echo "#                       For more info run"
  echo "#                       'invdev.sh $invinstance help'"
  echo "#  sourcerc             Run 'eval \$(invdev.sh sourcerc)'"
  echo "#                       to source Invenio development aliases:"
  echo "#                       'invd' for 'invdev.sh $invinstance"
  echo "#                       'dco' for Docker Compose."
  echo "#                       'etc."
  echo "#  -h                   Help"
}


if [ "$1" != "" ]
then
  case $1 in
    init)                 init
                          ;;
    install)              install_modules
                          ;;
    ${invinstance_short}) coddev "$@"
                          ;;
    ${invinstance})       coddev "$@"
                          ;;
    reset)                echo "# Run following commands to reset development"
                          echo "# ALL CHANGES to development environment"
                          echo "# WILL BE LOST after running this."
                          echo "# eval \$(invdev.sh reset)"
                          echo "docker-compose down -v --remove-orphans"
                          echo "docker-compose -f $dcofile up"
                          ;;
    sourcerc)             aliases
                          ;;
    -h | --help )         usage
                          exit
                          ;;
  esac
else
  usage
fi
