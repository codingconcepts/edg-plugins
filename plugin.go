package edgplugins

import "math/rand/v2"

// Rng is a seeded random number generator shared with the edg host process.
// When edg starts with --rng-seed, this is set to the same deterministic RNG
// used by built-in functions. Use this instead of math/rand for reproducible output.
var Rng *rand.Rand

// Function describes a single function contributed by a plugin.
type Function struct {
	Name        string
	Fn          any
	Description string
	Example     string
}

// Plugin is the interface that plugin .so files must implement.
// The exported symbol "EdgPlugin" must implement this interface.
//
// Plugin functions must be safe for concurrent use - they may be
// called from multiple workers simultaneously.
type Plugin interface {
	Name() string
	Functions() []Function
}
