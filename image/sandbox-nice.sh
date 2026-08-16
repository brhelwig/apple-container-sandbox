# shellcheck shell=sh
# Background work: what the sandbox does to a process that must lose the
# contest for CPU, disk and memory rather than the session losing it. Killing a
# build costs a build; killing claude or zellij costs the session.
#
# sandbox_deprioritize applies the three settings to the shell that calls it,
# and all three are inherited, so every process started afterwards carries
# them. Call it from a process, never from a subshell: $$ is the outer shell in
# a subshell, and the wrong process would be the one demoted.
#
# Two of the three are one-way for an unprivileged process: nice cannot go back
# down without CAP_SYS_NICE, and oom_score_adj cannot go below where the
# process started without CAP_SYS_RESOURCE. A sandbox has neither, which is why
# claude is not protected directly instead. Only 1000 puts a command ahead of a
# claude that has grown to most of the sandbox.
sandbox_deprioritize() {
    renice -n 10 -p $$ > /dev/null 2>&1
    ionice -c 3 -p $$ > /dev/null 2>&1
    echo 1000 > "/proc/$$/oom_score_adj" 2>/dev/null
    return 0
}

# Claude Code spawns each command it runs in its own non-interactive zsh with
# CLAUDECODE in the environment, and /etc/zsh/zshenv is the file such a shell
# reads. So this catches every command Claude runs, and nothing else: a shell
# you type in, zellij, and claude itself keep their own standing.
if [ -n "${CLAUDECODE:-}" ]; then
    sandbox_deprioritize
fi
