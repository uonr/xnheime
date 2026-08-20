fn main() {
    let mut bridge = cxx_build::bridge("src/lib.rs");
    bridge.std("c++17");
    if std::env::var("OPT_LEVEL").as_deref() == Ok("0") {
        // Hardened toolchains require optimization for _FORTIFY_SOURCE. Only
        // the generated CXX glue is optimized here; Rust debug code is not.
        bridge.opt_level(1);
    }
    bridge.compile("xnheime-cxxbridge");
    println!("cargo:rerun-if-changed=src/lib.rs");
}
