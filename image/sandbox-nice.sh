# shellcheck shell=sh

# Call from a process, never a subshell: $$ is the outer shell there, and the
# wrong process would be the one changed.
#
# 1000 rather than something milder because a sandbox without k3s holds no
# CAP_SYS_RESOURCE, so oom_score_adj cannot go back below where a process
# started. Claude cannot be made harder to kill, only its commands easier.
sandbox_deprioritize() {
    renice -n 10 -p $$ > /dev/null 2>&1
    ionice -c 3 -p $$ > /dev/null 2>&1
    echo 1000 > "/proc/$$/oom_score_adj" 2>/dev/null
    return 0
}

# Claude Code spawns each command it runs in a non-interactive zsh with
# CLAUDECODE set, and /etc/zsh/zshenv is the file such a shell reads. So this
# catches every command Claude runs and nothing else: a shell you type in,
# zellij and claude itself keep their own standing.
if [ -n "${CLAUDECODE:-}" ]; then
    sandbox_deprioritize
fi
