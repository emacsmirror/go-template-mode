# Provenance

## Current Implementation

Beginning with version 2.0.0, Go template action scanning and fontification
are implemented in `go-template-mode-font-lock.el` with reference to the
official Go 1.26.7 `text/template` documentation and lexer, parser, and
builtin-function sources:

- <https://pkg.go.dev/text/template@go1.26.7>
- <https://github.com/golang/go/blob/go1.26.7/src/text/template/parse/lex.go>
- <https://github.com/golang/go/blob/go1.26.7/src/text/template/parse/parse.go>
- <https://github.com/golang/go/blob/go1.26.7/src/text/template/funcs.go>

Version 2.0.0 replaces the 1.0.0/Gist-derived fontification internals with a
newly structured action-bounded scanner and standard Font Lock integration.
Current production source retains none of the earlier parser/cache symbols,
comment matcher, HTML tag tables, or global regular-expression keyword table.
The major-mode adapter preserves established package behavior such as mode
identity, comment settings, tab preference, and file associations. This was
not a formal clean-room process because the earlier implementations had
already been inspected.

## Versions Through 1.0.0

Version 1.0.0 contained portions derived in part from this 2012 GitHub Gist:

- Gist: <https://gist.github.com/anonymous/1654113>
- Revision: `dcd12037308446179f26f7d2ab2c034a1e995d2e`

GitHub displays the Gist author as "Anonymous." A contemporaneous golang-nuts
post by Patrick Higgins says that he created the mode and links that exact
Gist for review:

- <https://groups.google.com/g/golang-nuts/c/03hDZVLeUIw>

The Gist contains no explicit copyright or license notice. The same post says
that its implementation used substantial code from Go's historical
`misc/emacs/go-mode.el`. The likely upstream version was distributed under
the Go repository's BSD-style license:

- <https://github.com/golang/go/blob/70ed0ac5889000fb712dac16e9dea8ef2fa4030f/misc/emacs/go-mode.el>
- <https://github.com/golang/go/blob/70ed0ac5889000fb712dac16e9dea8ef2fa4030f/LICENSE>

The parser and cache implementation most clearly adapted from that historical
Go mode was not present in this repository's compact 1.0.0 implementation.
Version 1.0.0 did retain or adapt the Gist's syntax-table setup, keyword and
builtin lists, HTML tag tables, Font Lock table shape, and template-comment
highlighting behavior.

## Scope of This Notice

This document records source history and the replacement performed for version
2.0.0. Attribution, documentation, and a version change do not by themselves
grant a license or retroactively resolve distribution of earlier versions.
Historical tags, repository history, and previously distributed artifacts are
separate provenance and compliance questions.
