package edgplugins

// WasmFunction describes a function for WASM plugin registration.
type WasmFunction struct {
	Name        string
	Fn          any
	Description string
	Example     string
}

// Register adds a function to the WASM plugin registry.
// Call this from init() in your plugin.
func Register(f WasmFunction) {
	wasmRegistry = append(wasmRegistry, f)
}

// SetPluginName sets the plugin name for the WASM manifest.
func SetPluginName(name string) {
	wasmPluginName = name
}

var (
	wasmPluginName string
	wasmRegistry   []WasmFunction
)
