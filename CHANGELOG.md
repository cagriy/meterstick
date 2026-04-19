# Changelog

## v1.1.2

### Features
- `--color <name>` option in `install.sh` to set the model name color at install time
- `model_color` field in `meterstick-config.json` read at runtime — change color without reinstalling
- Vivid 256-color definitions for `green` and `blue` (replaces dim ANSI defaults)
- Config path patched in installed script when using `--config-dir` with a non-default path

### Available colors
`orange` `white` `green` `red` `cyan` `blue` `light_gray` `gray` `dark_gray` `yellow` `bold_red`

## v1.0.0

### Features
- Model info display (e.g., "Opus 4.6")
- Directory context (current directory name)
- Git branch status with color coding (green = clean, red = uncommitted changes)
- Context window usage percentage with color coding and token counts
- Real-time rate limit tracking via Anthropic OAuth API (5-hour and weekly windows)
- Configurable section order and visibility via `~/.claude/meterstick-config.json`
- Interactive installer and uninstaller
- 30-second OAuth cache and 5-second git status cache
