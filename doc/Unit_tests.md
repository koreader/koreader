# Unit Tests

Unit tests are written for [busted](https://lunarmodules.github.io/busted/)
(a version is automatically provided by the build system), and executed in
parallel with the meson test runner.

You can run them with `./kodev test`, examples:

- to run all tests (frontend & base): `./kodev test`
- frontend only: `./kodev test front`
- to run one specific base test: `./kodev test base util`
- to run one specific frontend test: `./kodev test front readerpanelnav`
- to list available tests: `./kodev test -l`

Check the output of `./kodev test -h` for the full usage.
