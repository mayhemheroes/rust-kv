#![no_main]
use libfuzzer_sys::fuzz_target;
use kv::*;

const MAX_LEN: usize = 10;

fuzz_target!(|data: &[u8]| {
    let mut cfg = Config::new(format!("{}{}", "./test/fuzzdb", if data.len() < 1 {0} else {data[0]%10})).temporary(true);
    let store = Store::new(cfg).expect("Error: Store");
    let test = store.bucket::<Raw, Raw>(Some("test")).expect("Error: Bucket");
    let mut idx = 0;
    while idx < data.len() {
        let mut idx1 = idx + MAX_LEN;
        let mut idx2 = idx1 + MAX_LEN;
        if idx1 > data.len() {
            idx1 = data.len() - 1;
        }
        
        if idx2 > data.len() {
            idx2 = data.len();
        }

        test.set(&Raw::from(&data[idx..idx1]), &Raw::from(&data[idx1..idx2]));

        idx = idx2;
    }
});
