#
# ~/.bashrc
#

# don't put duplicate lines in the history. See bash(1) for more options
# ... or force ignoredups and ignorespace
HISTCONTROL=ignoredups:ignorespace

# append to the history file, don't overwrite it
shopt -s histappend

[ -f $HOME/.shellsrc ] && . $HOME/.shellsrc

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=10000000
HISTFILESIZE=200000000

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

