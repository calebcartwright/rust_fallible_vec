Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-WithEnvironment([System.Collections.IDictionary] $Environment, [scriptblock]$ScriptBlock) {
    try {
        # Set the environment.
        foreach ($item in $Environment.GetEnumerator()) {
            Set-Item -Path $item.Key -Value $item.Value
        }
        & $ScriptBlock
    } finally {
        # Cleanup the environment afterwards.
        foreach ($item in $Environment.Keys) {
            if (Test-Path -Path $item) {
                Remove-Item $item
            }
        }
    }
}

Invoke-WithEnvironment `
    -Environment @{
        # Enable unstable features on stable toolchain.
        'env:RUSTC_BOOTSTRAP' = '1';
        # Fail 'cargo doc' on warnings.
        'env:RUSTDOCFLAGS' = '-D warnings';
    } `
    -ScriptBlock {
        #
        # Run tests
        #
        cargo test --locked

        #
        # Lint and check formatting.
        #
        cargo clippy --locked -- -D warnings
        cargo fmt --check

        #
        # Check docs
        #
        cargo doc --locked

        #
        # Verify that we can build with #[cfg(no_global_oom_handling)] enabled.
        #

        # Find target (required for `build-std`).
        [string] $target = ''
        if ($Global:IsWindows) {
            $target = 'x86_64-pc-windows-msvc'
        } elseif ($Global:IsLinux) {
            $target = 'x86_64-unknown-linux-gnu'
        } elseif ($Global:IsMacOS) {
            $target = 'x86_64-apple-darwin'
        } else {
            throw 'Unknown OS - Only Windows, Linux and MacOS are supported'
        }
        Invoke-WithEnvironment `
            -Environment @{
                # `no_global_oom_handling` disable all infallible allocation functions
                # in the standard library.
                'env:RUSTFLAGS' = '--cfg no_global_oom_handling';
            } `
            -ScriptBlock { cargo build --locked -Z build-std=core,alloc --target $target }
}

# Run tests under miri
rustup toolchain install nightly --component miri
cargo +nightly miri setup
cargo +nightly miri test
