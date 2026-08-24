# Frotz binary provenance and corresponding source

LANTERN distributes the dumb-terminal Frotz executable as `runtime/x86_64-linux/dfrotz`.

## Upstream source

- Project: <https://gitlab.com/DavidGriffith/frotz>
- Version/tag: `2.55`
- Commit: `acf205585a9472d27c07c0fe62da4b8bc89d1ec7`
- License: GPL-2.0-or-later; see `../COPYING`
- Complete source archive shipped with LANTERN: `source/frotz-2.55.tar.gz`

The included archive was generated from that exact commit with:

```bash
git archive --format=tar.gz --prefix=frotz-2.55/ \
  acf205585a9472d27c07c0fe62da4b8bc89d1ec7 > frotz-2.55.tar.gz
```

## Distributed executable

The executable was copied unchanged from the signed Arch Linux package:

- Package: `frotz-dumb 2.55-1`, `x86_64`
- Package URL used: `https://mirror.omarchy.org/extra/os/x86_64/frotz-dumb-2.55-1-x86_64.pkg.tar.zst`
- Package SHA-256: `ee48d8bb470dc160da9521982c25c83a25f1f7b7c52a1817417ed531e09126af`
- Package signature key: `89DB0CFD528EC1A92E0C11341736C918F59A5673`
- Signer: Alexander Epaneshnikov, Arch Linux packager
- Extracted executable SHA-256: `5da9c0887299187cebb643308ec24844115e1a52f61303a9090906114f139c8e`
- Runtime dependency reported by the package: glibc

The package signature was verified with Arch's `pacman-key --verify` before extraction. The exact Arch packaging recipe is retained under `arch/` at packaging commit `883616bcff7a79c626b6d5d09812db74d134bce5` (tag `2.55-1`). It builds the dumb interface with:

```bash
make PREFIX=/usr dumb
```

## Rebuild

On a glibc Linux system with a C toolchain and `make`:

```bash
tar -xzf source/frotz-2.55.tar.gz
cd frotz-2.55
make PREFIX=/usr dumb
```

The resulting executable is `dfrotz`. Compiler and linker versions can change its byte-for-byte checksum; functional source correspondence, rather than reproducibility of the Arch build environment, is the purpose of this recipe.
