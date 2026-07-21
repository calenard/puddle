// Package assets holds static resources embedded in the puddle binary.
// Currently just the puddle logo used by the tui welcome banner.
package assets

import _ "embed"

// LogoPNG is the pixel-art puddle `z` logo as PNG bytes.
// Used by the interactive welcome banner; decoded once and rasterized
// to Unicode half-blocks so it renders on any terminal without needing
// inline image support.
//
//go:embed puddle-logo.png
var LogoPNG []byte
