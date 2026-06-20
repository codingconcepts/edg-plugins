package main

import (
	"fmt"

	edgplugins "github.com/codingconcepts/edg-plugins/go"
)

func init() {
	edgplugins.SetPluginName("go_example")
	edgplugins.Register(edgplugins.WasmFunction{
		Name:        "hello",
		Fn:          hello,
		Description: "Greet by name.",
		Example:     "hello('world')",
	})
	edgplugins.Register(edgplugins.WasmFunction{
		Name:        "dice",
		Fn:          dice,
		Description: "Roll an N-sided die.",
		Example:     "dice(6)",
	})
}

func hello(name string) string {
	return fmt.Sprintf("Hello, %s!", name)
}

func dice(sides int) int {
	return edgplugins.Rng.IntN(sides) + 1
}

func main() {}
