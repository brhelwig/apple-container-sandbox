# Show the sandbox name (== container hostname) in the prompt so it's
# unmistakable that this shell is inside a sandbox, not on the host. Sourced
# after the theme sets PROMPT, so it wraps whatever prompt is in effect.
PROMPT="%F{magenta}📦 %m%f ${PROMPT}"
