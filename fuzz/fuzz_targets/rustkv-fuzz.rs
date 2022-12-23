#![no_main]

use libfuzzer_sys::fuzz_target;

use kv::*;

fuzz_target!(|data: Vec<(Vec<u8>, Vec<u8>)>| {
    let cfg = Config::new("./test/fuzzdb").temporary(true);
    if let Ok(store) = Store::new(cfg) {
        let test = store.bucket::<Raw, Raw>(Some("test")).unwrap();

        for (k, v) in data {
            let _ = test.set(&Raw::from(k), &Raw::from(v));
        }
    };
});
