#![no_main]
// Additive Mayhem harness — mirrors upstream fuzz/fuzz_targets/rustkv-fuzz.rs, but
// rooted under /tmp. Mayhem mounts the commit image read-only during coverage
// collection, so the upstream harness's relative "./test/fuzzdb" path (created under
// the read-only /mayhem cwd) aborts every input and reports 0 edges. Using a
// per-process /tmp path keeps the exercised code identical while staying writable.
use libfuzzer_sys::fuzz_target;
use kv::*;

const MAX_LEN: usize = 10;

fuzz_target!(|data: &[u8]| {
    let sub = if data.len() < 1 { 0 } else { data[0] % 10 };
    let path = format!("/tmp/rustkv-fuzzdb/{}-{}", std::process::id(), sub);
    let cfg = Config::new(path).temporary(true);
    let store = Store::new(cfg).expect("Error: Store");
    let test = store.bucket::<Raw, Raw>(Some("test")).expect("Error: Bucket");
    let mut idx = 0;
    while idx < data.len() {
        let idx1 = idx + MAX_LEN;
        let mut idx1 = if idx1 > data.len() { data.len() - 1 } else { idx1 };
        let idx2 = idx1 + MAX_LEN;
        let idx2 = if idx2 > data.len() { data.len() } else { idx2 };
        // Guard the slice bounds (data.len()-1 can drop below idx for short inputs).
        if idx1 < idx {
            idx1 = idx;
        }
        let _ = test.set(&Raw::from(&data[idx..idx1]), &Raw::from(&data[idx1..idx2]));
        idx = idx2;
    }
});
