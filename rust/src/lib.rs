pub use serde_json::{self, Value, to_value};

use serde::Serialize;
use std::cell::RefCell;

thread_local! {
    static ALLOC_BUF: RefCell<Vec<u8>> = RefCell::new(Vec::new());
    static RNG_STATE: RefCell<u64> = RefCell::new(0);
}

pub fn alloc_impl(size: i32) -> i32 {
    ALLOC_BUF.with(|buf| {
        let mut buf = buf.borrow_mut();
        buf.resize(size as usize, 0);
        buf.as_ptr() as i32
    })
}

pub fn write_to_memory(data: &[u8]) -> i64 {
    let ptr = alloc_impl(data.len() as i32);
    unsafe {
        std::ptr::copy_nonoverlapping(data.as_ptr(), ptr as *mut u8, data.len());
    }
    ((ptr as i64) << 32) | (data.len() as i64)
}

pub fn write_error(msg: &str) -> i64 {
    let data = format!(r#"{{"error":"{msg}"}}"#);
    write_to_memory(data.as_bytes())
}

pub fn write_describe(manifest: &Manifest) -> i64 {
    let data = serde_json::to_vec(manifest).unwrap();
    write_to_memory(&data)
}

pub fn dispatch(
    fn_id: i32,
    arg_ptr: i32,
    arg_len: i32,
    handlers: &[fn(&[Value]) -> Result<Value, String>],
) -> i64 {
    let arg_data = unsafe { std::slice::from_raw_parts(arg_ptr as *const u8, arg_len as usize) };
    let args: Vec<Value> = match serde_json::from_slice(arg_data) {
        Ok(v) => v,
        Err(e) => return write_error(&format!("unmarshal args: {e}")),
    };

    let idx = fn_id as usize;
    if idx >= handlers.len() {
        return write_error("invalid function ID");
    }

    match handlers[idx](&args) {
        Ok(value) => {
            let data = serde_json::to_vec(&value).unwrap();
            write_to_memory(&data)
        }
        Err(msg) => write_error(&msg),
    }
}

pub fn seed_rng_impl(seed: i64) {
    RNG_STATE.with(|s| *s.borrow_mut() = seed as u64);
}

/// Returns a pseudo-random u64 (SplitMix64).
pub fn rng_u64() -> u64 {
    RNG_STATE.with(|s| {
        let mut state = s.borrow_mut();
        *state = state.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = *state;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    })
}

/// Returns a random integer in [0, n).
pub fn rng_intn(n: u64) -> u64 {
    rng_u64() % n
}

#[derive(Serialize)]
pub struct Manifest<'a> {
    pub name: &'a str,
    pub functions: Vec<FuncDesc<'a>>,
}

#[derive(Serialize)]
pub struct FuncDesc<'a> {
    pub name: &'a str,
    pub description: &'a str,
    pub example: &'a str,
    pub params: Vec<ParamDesc<'a>>,
    pub returns: &'a str,
}

#[derive(Serialize)]
pub struct ParamDesc<'a> {
    pub name: &'a str,
    #[serde(rename = "type")]
    pub param_type: &'a str,
}

pub trait EdgType: Sized {
    const TYPE_NAME: &'static str;
    fn from_value(v: &Value) -> Result<Self, String>;
}

impl EdgType for String {
    const TYPE_NAME: &'static str = "string";
    fn from_value(v: &Value) -> Result<Self, String> {
        v.as_str()
            .map(|s| s.to_string())
            .ok_or_else(|| "expected string".to_string())
    }
}

impl EdgType for i64 {
    const TYPE_NAME: &'static str = "int";
    fn from_value(v: &Value) -> Result<Self, String> {
        v.as_i64().ok_or_else(|| "expected int".to_string())
    }
}

impl EdgType for f64 {
    const TYPE_NAME: &'static str = "float";
    fn from_value(v: &Value) -> Result<Self, String> {
        v.as_f64().ok_or_else(|| "expected float".to_string())
    }
}

impl EdgType for bool {
    const TYPE_NAME: &'static str = "bool";
    fn from_value(v: &Value) -> Result<Self, String> {
        v.as_bool().ok_or_else(|| "expected bool".to_string())
    }
}

#[macro_export]
macro_rules! edg_plugin {
    (
        name: $plugin_name:expr,
        functions: {
            $(
                $fn_name:ident ( $( $param:ident : $ptype:ty ),* $(,)? ) -> $ret:ty,
                $desc:expr,
                $example:expr
            );+ $(;)?
        }
    ) => {
        #[no_mangle]
        pub extern "C" fn alloc(size: i32) -> i32 {
            $crate::alloc_impl(size)
        }

        #[no_mangle]
        pub extern "C" fn seed_rng(seed: i64) {
            $crate::seed_rng_impl(seed)
        }

        #[no_mangle]
        pub extern "C" fn describe() -> i64 {
            let manifest = $crate::Manifest {
                name: $plugin_name,
                functions: vec![
                    $(
                        $crate::FuncDesc {
                            name: stringify!($fn_name),
                            description: $desc,
                            example: $example,
                            params: vec![
                                $(
                                    $crate::ParamDesc {
                                        name: stringify!($param),
                                        param_type: <$ptype as $crate::EdgType>::TYPE_NAME,
                                    },
                                )*
                            ],
                            returns: <$ret as $crate::EdgType>::TYPE_NAME,
                        },
                    )+
                ],
            };
            $crate::write_describe(&manifest)
        }

        #[no_mangle]
        pub extern "C" fn call(fn_id: i32, arg_ptr: i32, arg_len: i32) -> i64 {
            $crate::dispatch(fn_id, arg_ptr, arg_len, &[
                $(
                    {
                        #[allow(unused_assignments, unused_variables, unused_mut)]
                        fn __edg_dispatch(args: &[$crate::Value]) -> Result<$crate::Value, String> {
                            let mut __edg_i: usize = 0;
                            $(
                                let $param = <$ptype as $crate::EdgType>::from_value(
                                    args.get(__edg_i).ok_or_else(|| format!(
                                        concat!(stringify!($fn_name), ": missing arg {}"), __edg_i
                                    ))?
                                ).map_err(|e| format!(
                                    concat!(stringify!($fn_name), ": ", stringify!($param), ": {}"), e
                                ))?;
                                __edg_i += 1;
                            )*
                            let __edg_result = $fn_name($($param),*);
                            Ok($crate::to_value(&__edg_result).unwrap())
                        }
                        __edg_dispatch as fn(&[$crate::Value]) -> Result<$crate::Value, String>
                    },
                )+
            ])
        }
    };
}
