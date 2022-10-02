FROM ghcr.io/evanrichter/cargo-fuzz as builder

ADD . /rust-kv
WORKDIR /rust-kv/fuzz
RUN cargo +nightly fuzz build 

FROM debian:bookworm
COPY --from=builder /rust-kv/fuzz/target/x86_64-unknown-linux-gnu/release/rustkv-fuzz /