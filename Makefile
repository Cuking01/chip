DESIGN ?= hello_rtl

.PHONY: bootstrap images check-tools sim synth flow shell-rtl shell-openlane clean clean-design disk

bootstrap:
	./scripts/bootstrap.sh

images:
	docker compose build rtl openlane

check-tools:
	./scripts/check_toolchain.sh

sim:
	./scripts/sim.sh $(DESIGN)

synth:
	./scripts/synth.sh $(DESIGN)

flow:
	./scripts/flow.sh $(DESIGN)

shell-rtl:
	docker compose run --rm rtl bash

shell-openlane:
	docker compose run --rm openlane bash

clean:
	./scripts/clean.sh

clean-design:
	./scripts/clean.sh $(DESIGN)

disk:
	du -sh build runs pdks 2>/dev/null || true
