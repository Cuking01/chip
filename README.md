# chip

Self-contained learning workspace for RTL simulation, synthesis, and OpenLane runs.
The host needs only Git, Docker Engine, and the Docker Compose plugin. All EDA tools
run in containers; source, PDKs, and generated files stay under this directory.

## First use

```bash
make bootstrap
make images
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

## Layout and versioning

- `designs/`: committed RTL, testbenches, constraints, and flow configurations.
- `docker/`, `scripts/`, `compose.yml`, `Makefile`: committed reproducible environment.
- `build/`: generated simulation/synthesis files; safe to delete.
- `runs/`: generated OpenLane results; safe to delete/recreate.
- `pdks/`: downloaded PDKs; not committed, but retained by `make clean`.
- `reports/`: commit only compact milestone summaries and selected evidence.

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
