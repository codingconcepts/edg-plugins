# edg-plugins

SDKs for writing [edg](https://github.com/codingconcepts/edg) plugins in Go, Rust, and Zig. Plugin authors import one of these libraries to register custom functions that become available in edg expressions.

Plugins compile to WASM (wasip1) and are loaded at runtime with `--plugin`.

## Go

### Install

```sh
go get github.com/codingconcepts/edg-plugins/go
```

### Write a plugin

```go
package main

import (
    "fmt"

    edgplugins "github.com/codingconcepts/edg-plugins/go"
)

func init() {
    edgplugins.SetPluginName("greetings")
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
```

### Build

```sh
GOOS=wasip1 GOARCH=wasm go build -o greetings.wasm .
```

### Deterministic output

Use `edgplugins.Rng` instead of `math/rand` for reproducible results with `--rng-seed`.

## Rust

### Install

```sh
cargo add edg-plugin
```

Or add to `Cargo.toml`:

```toml
[dependencies]
edg-plugin = "0.1"
```

Your crate must be a `cdylib`:

```toml
[lib]
crate-type = ["cdylib"]
```

### Write a plugin

```rust
use edg_plugin::*;

fn card_mask(input: String, visible: i64) -> String {
    let chars: Vec<char> = input.chars().collect();
    chars.iter().enumerate()
        .map(|(i, &c)| {
            if i < chars.len().saturating_sub(visible as usize) { '*' } else { c }
        })
        .collect()
}

fn initials(name: String) -> String {
    name.split_whitespace()
        .filter_map(|w| w.chars().next())
        .map(|c| c.to_uppercase().next().unwrap_or(c))
        .collect()
}

edg_plugin! {
    name: "masking",
    functions: {
        card_mask(input: String, visible: i64) -> String,
        "Mask all but the last N characters of a string.",
        "card_mask('4111111111111111', 4)";

        initials(name: String) -> String,
        "Extract uppercase initials from a full name.",
        "initials('Jane Doe')";
    }
}
```

Supported parameter/return types: `String`, `i64`, `f64`, `bool`.

For deterministic output, use `edg_plugin::rng_u64()` or `edg_plugin::rng_intn(n)`.

### Build

```sh
rustup target add wasm32-wasip1
cargo build --target wasm32-wasip1 --release
```

The `.wasm` file will be at `target/wasm32-wasip1/release/<name>.wasm`.

## Zig

### Install

Add the dependency to your `build.zig.zon`:

```zig
.dependencies = .{
    .edg_plugin = .{
        .url = "https://github.com/codingconcepts/edg-plugins/archive/refs/tags/<VERSION>.tar.gz#zig",
        .hash = "...",
    },
},
```

Then import the module in your `build.zig`:

```zig
const edg_dep = b.dependency("edg_plugin", .{});

const exe = b.addExecutable(.{
    .name = "my_plugin",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        }),
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "edg", .module = edg_dep.module("edg") },
        },
    }),
});
exe.entry = .disabled;
exe.rdynamic = true;
b.installArtifact(exe);
```

### Write a plugin

```zig
const edg = @import("edg");

fn slug(input: []const u8) []const u8 {
    var pos: usize = 0;
    for (input) |c| {
        if (pos >= edg.result_buf.len) break;
        if (c >= 'A' and c <= 'Z') {
            edg.result_buf[pos] = c + 32;
            pos += 1;
        } else if ((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9')) {
            edg.result_buf[pos] = c;
            pos += 1;
        } else if (c == ' ' or c == '_') {
            if (pos > 0 and edg.result_buf[pos - 1] != '-') {
                edg.result_buf[pos] = '-';
                pos += 1;
            }
        }
    }
    while (pos > 0 and edg.result_buf[pos - 1] == '-') pos -= 1;
    return edg.result_buf[0..pos];
}

const p = edg.plugin(.{
    .name = "text_utils",
    .functions = .{
        .{ .name = "slug", .handler = slug, .desc = "Convert to URL slug.", .example = "slug('Hello World')" },
    },
});

export fn alloc(size: i32) i32 { return edg.allocImpl(size); }
export fn describe() i64 { return p.describe(); }
export fn call(fn_id: i32, arg_ptr: i32, arg_len: i32) i64 { return p.call(fn_id, arg_ptr, arg_len); }
export fn seed_rng(seed: i64) void { edg.seedRng(seed); }
```

Supported parameter/return types: `[]const u8` (string), `i64` (int), `f64` (float), `bool`.

Write string results into `edg.result_buf` and return a slice of it. For deterministic output, use `edg.rngU64()` or `edg.rngIntn(n)`.

### Build

```sh
zig build
```

The `.wasm` file will be at `zig-out/bin/<name>.wasm`.

## Use a plugin

```sh
edg run --config workload.edg --url "$DATABASE_URL" --plugin ./my_plugin.wasm
```

Plugin functions work anywhere built-in functions do — seed args, run args, conditionals, and user-defined expressions.

## Thread safety

Plugin functions may be called concurrently from multiple workers. Avoid shared mutable state or protect it with synchronisation primitives.
