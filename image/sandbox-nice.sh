sandbox_deprioritize() {
    renice -n 10 -p $$ > /dev/null 2>&1
    ionice -c 3 -p $$ > /dev/null 2>&1
    echo 1000 > "/proc/$$/oom_score_adj" 2>/dev/null
    return 0
}

if [ -n "${CLAUDECODE:-}" ]; then
    sandbox_deprioritize
fi
