# Keep the library's own source list and rules. JWasm interprets the JWASM
# environment variable as command-line options, not as its executable path.
include GNUmakefile
unexport JWASM JWLINK
