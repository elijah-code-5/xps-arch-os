# Faster rebuilds: compiler cache and parallel make
export PATH="/usr/lib/ccache/bin:$PATH"
export MAKEFLAGS="-j$(nproc)"
export CCACHE_MAXSIZE=20G
