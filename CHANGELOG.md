# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release.
- `TermRequest` based OSC relay from `:terminal` children to host terminal.
- Allow/deny selector filtering, default `allow = { "9;4" }`.
- `scope = "focused"` to avoid races between multiple inner terminals.
- tmux DCS passthrough wrapping (`multiplex = "auto"`).
- Auto-reset on `TermClose` / `VimLeavePre`.
- `User OscRelay` autocmd for in-nvim integrations.
- `:checkhealth osc-relay`.
