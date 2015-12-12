# vim: ft=zsh
# dot - dotfiles management framework

# Version:    1.1
# Repository: https://github.com/ssh0/dotfiles.git
# Author:     ssh0 (Shotaro Fujimoto)
# License:    MIT

dot_main() {

  # Local variables
  local clone_repository dotdir dotlink linkfiles home_pattern dotdir_pattern
  local dotset_interactive dotset_verbose diffcmd edit2filecmd
  local dot_edit_default_editor
  local black red green yellow blue purple cyan white
  local color_message color_error color_notice

  # ---------------------------------------------------------------------------
  # Default settings                                                        {{{
  # ---------------------------------------------------------------------------

  clone_repository="${DOT_REPO:-"https://github.com/ssh0/dotfiles.git"}"

  dotdir="${DOT_DIR:-"$HOME/.dotfiles"}"
  dotlink="${DOT_LINK:-"$dotdir/dotlink"}"
  linkfiles=("${dotlink}")

  home_pattern="s/\/home\/$USER\///p"
  dotdir_pattern="s/\/home\/$USER\/\.dotfiles\///p"

  dotset_interactive=true
  dotset_verbose=false

  if hash colordiff; then
    diffcmd="colordiff -u"
  else
    diffcmd='diff -u'
  fi

  if hash vimdiff; then
    edit2filecmd='vimdiff'
  else
    edit2filecmd=${diffcmd}
  fi

  dot_edit_default_editor=''

  # color palette
  black=30
  red=31
  green=32
  yellow=33
  blue=34
  purple=35
  cyan=36
  white=37

  color_message=${blue}
  color_error=${red}
  color_notice=${yellow}

  # ------------------------------------------------------------------------}}}
  # Load user configuration                                                 {{{
  # ---------------------------------------------------------------------------


  dotbundle() {
    if [ -e "$1" ]; then
      source "$1"
    fi
  }

  # path to the config file
  local dotrc="$dotdir/dotrc"
  dotbundle "${dotrc}"

  # ------------------------------------------------------------------------}}}

  # get the path to this script
  local dotscriptpath="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"

  usage() {
    cat << EOF

NAME
      dot - manages symbolic links for dotfiles.

USAGE
      dot [-h|--help] <command> [<args>]

COMMAND
      clone     Clone ssh0's dotfile repository on your computer.

      pull      Pull remote dotfile repository (by git).

      set       Make symbolic link interactively.
                This command sets symbolic links configured in '$dotlink'.

      add       Move the file to the dotfile dir and make an symbolic link.

      edit      Edit dotlink file '$dotlink'.

      unlink    Unlink the selected symbolic link and copy its original file
                from the dotfile repository.

      clear     Remove the all symbolic link in the config file '$dotlink'.

      config    Edit (or create) rcfile '$dotrc'.

OPTION
      -h,--help:    Show this help message.

COMMAND OPTIONS
      clone [<dir>]
          Clone ${clone_repository} onto the specified direction.
          default: ~/.dotfiles

      set [-i][-v]
          -i: No interaction mode(skip all conflicts and do nothing).
          -v: Print verbose messages.

      add [-m <message>] original_file [dotfile_direction]
          -m <message>: Add your message for dotlink file.

EOF
    return 1
  }


  cecho() {
    local color=$1
    shift
    echo -e "\033[${color}m"$@"\033[00m"
  }


  makeline() {
    local columns line
    columns=$(tput cols)
    if [[ $columns -gt 70 ]]; then
      columns=70
    fi
    line=$(printf '%*s\n' "$columns" '' | tr ' ' -)
    echo "${line}"
  }


  get_fullpath() {
    echo "$(cd "$(dirname "$1")" && pwd)"/"$(basename "$1")"
  }


  path_without_home() {
    get_fullpath "$1" | sed -ne "${home_pattern}"
  }


  path_without_dotdir() {
    get_fullpath "$1" | sed -ne "${dotdir_pattern}"
  }


  dot_clone() {
    local cloneto confirm
    cloneto="${1:-"${dotdir}"}"
    cecho ${color_message} "\ngit clone ${clone_repository} ${cloneto}"
    makeline
    echo "Continue? [y/N]"
    local confirm; read confirm
    if [ "$confirm" != "y" ]; then
      echo "Aborted."
      echo ""
      echo "If you want to clone other repository, change environment variable DOT_REPO."
      echo "    export DOT_REPO=https://github.com/Your_Username/dotfiles.git"
      echo "Set the directory to clone by:"
      echo "    dot clone ~/dotfiles"
      echo "    export DOT_DIR=\$HOME/dotfiles"
      return 1
    fi
    git clone "${clone_repository}" "${cloneto}"
  }


  dot_pull() {
    local cwd="$(pwd)"
    if [ "$1" = "--self" ]; then
      cd "${dotscriptpath}" && git pull
    else
      # git pull
      cecho ${color_message} "\ncd ${dotdir} && git pull"
      makeline
      cd "${dotdir}" && git pull
    fi
    cd "$cwd"
  }


  dot_set() {
    # option handling
    while getopts iv OPT
    do
      case $OPT in
        "i" ) dotset_interactive=false ;;
        "v" ) dotset_verbose=true ;;
      esac
    done


    info() {
      if ${dotset_verbose}; then
        # verbose message
        echo ""
        echo "${1} -> ${2}"
      fi
    }

    local mklink
    if ${dotset_verbose}; then
      mklink="ln -sv"
    else
      mklink="ln -s"
    fi


    _dot_set() {
      local l
      for l in $(grep -Ev '^#' "$1" | grep -Ev '^$'); do
        dotfile="${dotdir}/$(echo "$l" | awk 'BEGIN {FS=","; }  { print $1; }')"
        orig="$HOME/$(echo "$l" | awk 'BEGIN {FS=","; }  { print $2; }')"
        if [ ! -e "${dotfile}" ]; then
          echo ""
          cecho ${color_error} "dotfile '${dotfile}' doesn't exist."
          continue
        fi

        # if directory doesn't exist: mkdir or not
        origdir="${orig%/*}"
        if [ ! -d "${origdir}" ]; then
          info "${orig}" "${dotfile}"
          cecho ${color_error} "'${origdir}' doesn't exist."
          if ${dotset_interactive}; then
            echo "[message] mkdir '${origdir}'? (Y/n):"
            echo -n ">>> "; local confirm; read confirm
            if [ "$confirm" != "n" ]; then
              mkdir -p "${origdir}"
            else
              echo "Aborted."
              break
            fi
          fi
        fi

        # if the file already exists
        if [ -e "${orig}" ]; then
          # if it is a symboliclink
          if [ -L "${orig}" ]; then
            linkto="$(readlink "${orig}")"
            info "${orig}" "${dotfile}"
            # if the link already be set: do nothing
            if [ "${linkto}" = "${dotfile}" ]; then
              ${dotset_verbose} && cecho ${color_message} "link '${orig}' already exists."
              continue
            # if the link is not refer to: unlink and re-link
            else
              cecho ${color_error} "link '${orig}' is NOT the link of '${dotfile}'."
              cecho ${color_error} "'${orig}' is link of '${linkto}'."
              if ${dotset_interactive}; then
                echo "[message] unlink and re-link for '${orig}'? (y/n):"
                local yn
                while echo -n ">>> "; read yn; do
                  case $yn in
                    [Yy] ) unlink "${orig}"
                          $mklink "${dotfile}" "${orig}"
                          break ;;
                    [Nn] ) break ;;
                    * ) echo "Please answer with y or n." ;;
                  esac
                done
              fi
              continue
            fi
          # if it is a file or directory: interaction menu
          else
            info "${orig}" "${dotfile}"
            if ${dotset_interactive}; then
              while true; do
                cecho ${color_notice} "'${orig}' already exists."
                echo "(d):show diff, (e):edit files, (f):overwrite, (b):make backup, (n):do nothing"
                echo -n ">>> "; local line; read line
                case $line in
                  [Dd] ) echo "${diffcmd} '${dotfile}' '${orig}'"
                        ${diffcmd} "${dotfile}" "${orig}"
                        echo ""
                        ;;
                  [Ee] ) echo "${edit2filecmd} '${dotfile}' '${orig}'"
                        ${edit2filecmd} "${dotfile}" "${orig}"
                        ;;
                  [Ff] ) if [ -d "${orig}" ]; then
                          rm -r "${orig}"
                        else
                          rm "${orig}"
                        fi
                        $mklink "${dotfile}" "${orig}"
                        break
                        ;;
                  [Bb] ) $mklink -b --suffix '.bak' "${dotfile}" "${orig}"
                        break
                        ;;
                  [Nn] ) break
                        ;;
                      *) echo "Please answer with [d/e/f/b/n]."
                        ;;
                esac
              done
            fi
          fi
        else
          # make symbolic file
          ln -sv "${dotfile}" "${orig}"
        fi
      done
      }

    local linkfile
    for linkfile in "${linkfiles[@]}"; do
      _dot_set "${linkfile}"
    done
  }


  dot_add() {
    # default message
    local message=""

    # option handling
    while getopts m:h OPT
    do
      case $OPT in
        "m" ) message="${OPTARG}";;
      esac
    done

    shift $((OPTIND-1))

    if [ ! -e "$1" ]; then
      cecho ${color_error} "'$1' doesn't exist."
      echo "Aborted."
      return 1
    fi


    orig_to_dot() {
      # mv from original path to dotdir
      local orig dot
      orig="$(get_fullpath "$1")"
      dot="$(get_fullpath "$2")"

      mv -i "${orig}" "${dot}"

      # link to orig path from dotfiles
      ln -siv "${dot}" "${orig}"
    }


    add_to_dotlink() {
      # add the configration to the config file.
      if [ ! "${message}" = "" ]; then
        echo "# ${message}" >> "${dotlink}"
      fi

      echo "$(path_without_dotdir "$2"),$(path_without_home "$1")" >> "${dotlink}"
    }

    # if the first arugument is not a symbolic link
    if [ ! -L "$1" ]; then
      # if the second arugument isn't provided
      if [ $# = 1 ]; then
        cecho ${color_message} "Suggestion:"
        echo "dot add -m '${message}' $1 ${dotdir}/$(path_without_home "$1")"
        echo ""
        echo "Continue? [y/N]"
        local confirm
        read confirm
        if [ "$confirm" != "y" ]; then
          echo "Aborted."
          return 1
        fi
        dot_add -m "${message}" "$1" "${dotdir}/$(path_without_home "$1")"
      # if the second arguments is provided (default action)
      elif [ $# = 2 ]; then
        if [ -e "$1" ]; then
          if [ ! -d "${2%/*}" ]; then
            cecho ${color_error} "'${2%/*}' doesn't exist."
            echo "[message] mkdir '${2%/*}'? (y/n):"
            local yn
            while echo -n ">>> "; read yn; do
              case $yn in
                [Yy] ) mkdir -p "${2%/*}"; break ;;
                [Nn] ) return 1 ;;
                * ) echo "Please answer with y or n." ;;
              esac
            done
            return 1
          fi
        else
          cecho ${color_error} "'$1' doesn't exist."
          return 1
        fi
        orig_to_dot "$1" "$2"
        add_to_dotlink "$1" "$2"
      # other: return error message
      else
        echo "Aborted."
        echo "Usage: 'dot add file'"
        echo "       'dot add file ${dotdir}/any/path/to/the/file'"
        return 1
      fi
    # if the first arugument is not a symbolic link
    else
      # write to dotlink
      local f
      for f in "$@"; do
        if [ ! -L "$f" ]; then
          echo "'$f' is not symbolic link."
        else
          # get the absolute path
          local abspath="$(readlink "$f")"
          if [ "$(path_without_dotdir "${abspath}")" = "" ]; then
            cecho ${color_error} "Target path (${abspath}) is not in the dotdir (${dotdir})."
            echo "Aborted."
            return 1
          fi
          # write to dotlink
          add_to_dotlink "$f" "${abspath}"
        fi
      done
    fi
  }


  dot_edit() {
    # open dotlink file
    if [ ! "${dot_edit_default_editor}" = "" ];then
      ${dot_edit_default_editor} "${dotlink}"
    elif hash "$EDITOR"; then
      $EDITOR "${dotlink}"
    else
      xdg-open "${dotlink}"
    fi
  }


  dot_unlink() {
    local f
    for f in "$@"; do
      if [ ! -L "$f" ]; then
        echo "'$f' is not symbolic link."
      else
        # get the file's path
        local currentpath="$(get_fullpath "$f")"

        # get the absolute path
        local abspath="$(readlink "$f")"

        # unlink the file
        unlink "$currentpath"

        # copy the file
        cp "$abspath" "$currentpath"
      fi
    done
  }


  dot_clear() {

    _dot_clear() {
      local l
      for l in $(grep -Ev '^#' "$1" | grep -Ev '^$'); do
        local orig="$HOME/$(echo "$l" | awk 'BEGIN {FS=","; }  { print $2; }')"
        if [ -L "${orig}" ]; then
          echo "unlink ${orig}"
          unlink "${orig}"
        fi
      done
    }

    local linkfile
    for linkfile in "${linkfiles[@]}"; do
      _dot_clear "${linkfile}"
    done
  }


  dot_config() {
    # init
    if [ ! -e "${dotrc}" ]; then
      cecho ${color_error} "'${dotrc}' doesn't exist."
      echo "[message] make configuration file ? (Y/n)"
      echo "cp ${dotscriptpath}/examples/dotrc ${dotrc}"
      makeline
      local confirm
      echo -n ">>> "; read confirm
      if [ "${confirm}" != "n" ]; then
        cp "${dotscriptpath}/examples/dotrc" "${dotrc}"
      else
        echo "Aborted."
        return 1
      fi
    fi

    # open dotrc file
    if [ ! "${dot_edit_default_editor}" = "" ];then
      ${dot_edit_default_editor} "${dotrc}"
    elif hash "$EDITOR"; then
      $EDITOR "${dotrc}"
    else
      xdg-open "${dotrc}"
    fi
  }

  # main command handling
  case "$1" in
    "clone")
      shift 1; dot_clone "$@"
      ;;
    "pull")
      shift 1; dot_pull "$@"
      ;;
    "set")
      shift 1; dot_set "$@"
      ;;
    "add")
      shift 1; dot_add "$@"
      ;;
    "edit")
      shift 1; dot_edit
      ;;
    "unlink")
      shift 1; dot_unlink "$@"
      ;;
    "clear")
      shift 1; dot_clear
      ;;
    "config")
      shift 1; dot_config
      ;;
    "-h"|"--help" )
      usage
      ;;
    *)
      echo "command '$1' not found."
      usage
      ;;
  esac

}


eval "alias ${DOT_COMMAND:="dot"}=dot_main"
export DOT_COMMAND

