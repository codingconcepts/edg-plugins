# edg-plugins

Public SDK for writing [edg](https://github.com/codingconcepts/edg) plugins. Plugin authors import this module to register custom Go functions that become available in edg expressions.

### Install

```sh
go get github.com/codingconcepts/edg-plugins
```

### Write a plugin

Create a Go `main` package that exports an `EdgPlugin` variable implementing `edgplugins.Plugin`:

```go
package main

import (
    "fmt"

    edgplugins "github.com/codingconcepts/edg-plugins"
)

type myPlugin struct{}

func (myPlugin) Name() string { return "greetings" }

func (myPlugin) Functions() []edgplugins.Function {
	return []edgplugins.Function{
		{
			Name:        "hello",
			Fn:          hello,
			Description: "Greet by name.",
			Example:     "hello('world')",
		},
		{
			Name:        "dice",
			Fn:          dice,
			Description: "Roll an N-sided die.",
			Example:     "dice(6)",
		},
	}
}

func hello(name string) string {
	return fmt.Sprintf("Hello, %s!", name)
}

func dice(sides int) int {
	return edgplugins.Rng.IntN(sides) + 1
}

var EdgPlugin edgplugins.Plugin = myPlugin{}

func main() {}
```

### Build

```sh
go build -buildmode=plugin -o greetings.so .
```

The plugin must be compiled with the same Go version and dependency versions as your edg binary (run `edg version` to display the Go version).

### Use

Given the greetings.so plugin:

```sh
edg run --config workload.edg --url "$DATABASE_URL" --plugin ./greetings.so
```

You'll have access to the following functions, as if they were built into edg itself:

* `hello(gen('firstname'))`
* `dice(20)`

Plugin functions work anywhere built-in functions do - seed args, run args, conditionals, and user-defined expressions.

### Deterministic output

Use `edgplugins.Rng` instead of `math/rand` for reproducible results with `--rng-seed`. edg sets this to its seeded RNG before any plugin function is called.

## Thread safety

Plugin functions may be called concurrently from multiple workers. Avoid shared mutable state or protect it with synchronisation primitives.
