_command_time_preexec() {
  # check excluded
  if [ -n "$ZSH_COMMAND_TIME_EXCLUDE" ]; then
    cmd="$1"
    for exc ($ZSH_COMMAND_TIME_EXCLUDE) do;
      if grep -qF "$exc" <<< "$cmd"; then
        # echo "command excluded: $exc"
        return
      fi
    done
  fi

  _command_time_timer=${timer:-$SECONDS}
  ZSH_COMMAND_TIME_MSG=${ZSH_COMMAND_TIME_MSG-"Time: %s"}
  ZSH_COMMAND_TIME_COLOR=${ZSH_COMMAND_TIME_COLOR-"white"}
  export ZSH_COMMAND_TIME=""
}

_command_time_precmd() {
  local timer_show
  if [ $_command_time_timer ]; then
    timer_show=$(($SECONDS - $_command_time_timer))
    if [ -n "$TTY" ] && [[ $timer_show -ge ${ZSH_COMMAND_TIME_MIN_SECONDS:-3} ]]; then
      export ZSH_COMMAND_TIME="$timer_show"
    if [[ "$ZSH_COMMAND_TIME" == *.* ]]; then
        zsh_command_time
      fi
    fi
    unset _command_time_timer
  fi
}

zsh_command_time() {
    local hours min sec timer_show
    if [ -n "$ZSH_COMMAND_TIME" ]; then
        # hours and minutes are calculated from the total seconds as integers
        typeset -i hours=$(( ZSH_COMMAND_TIME / 3600))
        typeset -i min=$(( ZSH_COMMAND_TIME / 60 % 60))
        if [[ "$ZSH_COMMAND_TIME" == *.* ]]; then
            # If SECONDS is a float, we limit the precision to 3 decimal places
            typeset -F 2 sec
        fi
        # secunds are calculated as float or integer automatically
        sec=$(( ZSH_COMMAND_TIME % 60 ))
        if [[ "$min" == 0 ]]; then
            timer_show="$fg[green]$sec s."
        elif [[ 1 -le "$min" && "$min" -le 3 ]]; then
            timer_show="$fg[yellow]$min min. $sec s."
        else
            if [[ "$hours" != 0 ]]; then
                timer_show="$fg[red]$hours h. $min min. $sec s."
            else
                timer_show="$fg[red]$min min. $sec s."
            fi
        fi
        printf "${ZSH_COMMAND_TIME_MSG}\n" "$timer_show"
    fi
}

precmd_functions+=(_command_time_precmd)
preexec_functions+=(_command_time_preexec)
