# Plugins

Use custom functions in edg workloads via the plugin system. This example builds a WASM plugin that provides `hello` and `dice` functions for seed and run queries. Implementations are provided in Go, Rust, and Zig.

### Build the plugin (Go)

The Go version uses the [edg-plugins](https://github.com/codingconcepts/edg-plugins) SDK. From the repo root:

```sh
GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o examples/plugins/go_example.wasm ./examples/plugins/go_example
```

### Build the plugin (Rust)

The Rust version implements the WASM ABI directly and provides `mask` and `initials` functions. From the repo root:

```sh
rustup target add wasm32-wasip1

cargo build --manifest-path examples/plugins/rust_example/Cargo.toml --target wasm32-wasip1 --release

cp examples/plugins/rust_example/target/wasm32-wasip1/release/rust_example.wasm examples/plugins/rust_example.wasm
```

### Build the plugin (Zig)

The Zig version implements the WASM ABI directly and provides `slug` and `rot13` functions. From the repo root:

```sh
(cd examples/plugins/zig_example && \
  zig build-exe -target wasm32-wasi -mcpu=mvp -OReleaseSmall -fno-entry \
    --export=alloc --export=describe --export=call \
    src/main.zig -femit-bin=zig_example.wasm)

mv examples/plugins/zig_example/zig_example.wasm examples/plugins/zig_example.wasm
```

### REPL example

```sh
edg repl \
  --plugin ./examples/plugins/go_example.wasm \
  --plugin ./examples/plugins/rust_example.wasm \
  --plugin ./examples/plugins/zig_example.wasm

# dice from go_example.wasm
>> dice(6)
3

# hello from go_example.wasm
>> hello('Rob')
Hello, Rob!

# card_mask from rust_example.wasm
>> card_mask("4111422243334444", 4)
************4444

# initials from rust_example.wasm
>> initials('Rob Reid')
RR

# slug from zig_example.wasm
>> slug('Hello World!')
hello-world

# rot13 from zig_example.wasm
>> rot13('Hello, World!')
Uryyb, Jbeyq!
```

### Start CockroachDB

```sh
cockroach demo --insecure --no-example-database
```

### Run the workload

```sh
edg all \
  --driver pgx \
  --url "postgres://root@localhost:26257?sslmode=disable" \
  --config examples/plugins/crdb.edg \
  --plugin ./examples/plugins/go_example.wasm \
  --plugin ./examples/plugins/rust_example.wasm \
  --plugin ./examples/plugins/zig_example.wasm
```

### Verify

```sql
SELECT * FROM greetings LIMIT 5;
```

Each row will have a greeting like "Hello, John!" and a random d20 roll.
