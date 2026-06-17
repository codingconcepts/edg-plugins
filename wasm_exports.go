//go:build wasip1

package edgplugins

import (
	"encoding/json"
	"math/rand/v2"
	"reflect"
	"unsafe"
)

var allocBuf []byte

//go:wasmexport alloc
func wasmAlloc(size int32) int32 {
	allocBuf = make([]byte, size)
	return int32(uintptr(unsafe.Pointer(&allocBuf[0])))
}

//go:wasmexport seed_rng
func wasmSeedRng(seed int64) {
	var s [32]byte
	u := uint64(seed)
	for i := range s {
		s[i] = byte(u >> (uint(i%8) * 8))
	}
	Rng = rand.New(rand.NewChaCha8(s))
}

type wasmManifest struct {
	Name      string         `json:"name"`
	Functions []wasmFuncDesc `json:"functions"`
}

type wasmFuncDesc struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Example     string          `json:"example"`
	Params      []wasmParamDesc `json:"params"`
	Returns     string          `json:"returns"`
}

type wasmParamDesc struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

//go:wasmexport describe
func wasmDescribe() int64 {
	m := wasmManifest{Name: wasmPluginName}
	for _, f := range wasmRegistry {
		fd := wasmFuncDesc{
			Name:        f.Name,
			Description: f.Description,
			Example:     f.Example,
		}
		ft := reflect.TypeOf(f.Fn)
		for i := 0; i < ft.NumIn(); i++ {
			fd.Params = append(fd.Params, wasmParamDesc{
				Name: ft.In(i).Name(),
				Type: goKindToType(ft.In(i)),
			})
		}
		if ft.NumOut() > 0 {
			fd.Returns = goKindToType(ft.Out(0))
		}
		m.Functions = append(m.Functions, fd)
	}

	data, _ := json.Marshal(m)
	return writeToMemory(data)
}

//go:wasmexport call
func wasmCall(fnID int32, argPtr int32, argLen int32) int64 {
	argData := unsafe.Slice((*byte)(unsafe.Pointer(uintptr(argPtr))), argLen)

	var args []json.RawMessage
	if err := json.Unmarshal(argData, &args); err != nil {
		return writeError("unmarshal args: " + err.Error())
	}

	if int(fnID) >= len(wasmRegistry) {
		return writeError("invalid function ID")
	}

	f := wasmRegistry[fnID]
	ft := reflect.TypeOf(f.Fn)
	fv := reflect.ValueOf(f.Fn)

	if len(args) != ft.NumIn() {
		return writeError(f.Name + ": wrong number of arguments")
	}

	in := make([]reflect.Value, ft.NumIn())
	for i := 0; i < ft.NumIn(); i++ {
		arg := reflect.New(ft.In(i))
		if err := json.Unmarshal(args[i], arg.Interface()); err != nil {
			return writeError(f.Name + ": arg " + ft.In(i).Name() + ": " + err.Error())
		}
		in[i] = arg.Elem()
	}

	out := fv.Call(in)

	if len(out) == 2 && out[1].Interface() != nil {
		if err, ok := out[1].Interface().(error); ok {
			return writeError(err.Error())
		}
	}

	var result any
	if len(out) > 0 {
		result = out[0].Interface()
	}

	data, _ := json.Marshal(result)
	return writeToMemory(data)
}

func writeToMemory(data []byte) int64 {
	ptr := wasmAlloc(int32(len(data)))
	copy(unsafe.Slice((*byte)(unsafe.Pointer(uintptr(ptr))), len(data)), data)
	return int64(ptr)<<32 | int64(len(data))
}

func writeError(msg string) int64 {
	data, _ := json.Marshal(map[string]string{"error": msg})
	return writeToMemory(data)
}

func goKindToType(t reflect.Type) string {
	switch t.Kind() {
	case reflect.String:
		return "string"
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return "int"
	case reflect.Float32, reflect.Float64:
		return "float"
	case reflect.Bool:
		return "bool"
	default:
		return "any"
	}
}
