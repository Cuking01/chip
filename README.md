# chip

Self-contained learning workspace for RTL simulation, synthesis, and OpenLane runs.
The host needs only Git, Docker Engine, and the Docker Compose plugin. All EDA tools
run in containers; source, PDKs, and generated files stay under this directory.

## First use

```bash
make bootstrap
make images
make check-tools
make sim DESIGN=hello_rtl
make synth DESIGN=hello_rtl
```

`make images` downloads/builds the RTL and OpenLane images. `make flow DESIGN=hello_rtl`
then starts an OpenLane run; its first PDK acquisition is stored in `pdks/` and can take
several GB. Pin `OPENLANE_IMAGE` in `.env` to a release or image digest before any
long-lived project.

Normal work never requires entering a container. The Make targets start short-lived
containers as the current host UID/GID, so generated files remain writable through Samba.
Interactive shells are available only for debugging: `make shell-rtl` and
`make shell-openlane`.

The RTL image uses OSS CAD Suite **2026-10-28**, pinned by release date and
SHA-256 in `docker/rtl/Dockerfile`. This snapshot includes Icarus **14.0 devel**
and Yosys **0.70+255**, with the integrated slang SystemVerilog frontend.
`make synth` uses `read_slang` and writes both a JSON netlist and plain Verilog
under `build/<design>/`. Package imports, packed structs/unions, and enum casts
are checked by `make check-tools`, including simulation of the lowered Verilog.
The archive targets Linux x86-64; an ARM host needs a matching tool archive.

Simulation, synthesis and the OpenLane lowering step first stage source files
under `build/<design>/preprocessed/`. `scripts/prepare_sv.py` converts matched
`{ ... }` statement blocks whose preceding token is `)`, `else`, `always_comb`,
or a statement-label colon (such as a case branch)
into `begin ... end`. Comments and strings are ignored, and concatenation and
replication braces are preserved, including braces after ternary-expression
colons. Other blocks (such as `initial begin`) still
use standard SystemVerilog syntax. This is a workspace syntax extension, not
standard SystemVerilog; invoking HDL tools directly bypasses the conversion.
Original files are never rewritten, and converted files retain original source
locations through the Verilog `line directive. Use relative quoted includes or
configured include directories so headers resolve in the staged directory tree.

OpenLane keeps its existing physical-design tools. Before `make flow`, its
configuration preprocessor resolves the selected RTL files, include paths,
defines, and parameter overrides. The upgraded frontend then elaborates them
into `build/<design>/<design>.flow.v`. OpenLane receives this ordinary Verilog;
top-level parameters are already applied and are cleared for its synthesis
step. Keep package files before their users in `VERILOG_FILES`. These commands
still require only Docker and the host shell.

To check the physical-flow entry without running place and route:

```bash
./scripts/flow.sh hello_rtl --to Yosys.Synthesis --condensed
```

## Layout and versioning

- `designs/`: committed RTL, testbenches, constraints, and flow configurations.
- `docker/`, `scripts/`, `compose.yml`, `Makefile`: committed reproducible environment.
- `build/`: generated simulation/synthesis files; safe to delete.
- `runs/`: generated OpenLane results; safe to delete/recreate.
- `pdks/`: downloaded PDKs; not committed, but retained by `make clean`.
- `reports/`: commit only compact milestone summaries and selected evidence.
- `tests/`: compatibility checks for the HDL toolchain.

Git deliberately ignores tool outputs, PDKs, waveforms, GDS/DEF/LEF, and local Docker
state. Publish a final GDS as a release artifact or with Git LFS only when that binary
is explicitly worth versioning.

## Maintenance

```bash
make disk                    # size of generated data
make clean-design DESIGN=hello_rtl  # remove one design's generated outputs
make clean                   # remove all build/ and runs/ outputs; retain PDKs
```

Docker image layers are managed by Docker itself and remain outside this repository's
working tree. The repository-controlled Dockerfiles and pinned image reference make the
environment reproducible without installing EDA packages on the host.
