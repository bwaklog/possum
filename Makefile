ifeq ($(OS), Windows_NT)
	BUILD_GENERATOR ?= "MinGW Makefile"	
else
	BUILD_GENERATOR ?= "Ninja"	
endif

all:
	@echo "\tmake [GENERATOR=<generator>] [docker-run|docker-run-clean]"
	@echo "\tmake [docker-build|clean]"
	@echo "\tmake [GENERATOR=<generator>] build # build on bare metal"

build:
	@echo "Using build generator $(GENERATOR)"
	@export BUILD_GENERATOR=$(BUILD_GENERATOR)
	@echo "Building the project"
	BUILD_GENERATOR="$(BUILD_GENERATOR)" zig build

## docker recipes
docker-run:
	docker run --rm --platform linux/arm64 \
		--mount type=bind,src=.,dst=/app \
		-e GENERATOR=$(GENERATOR) \
		possum:latest

docker-run-clean: clean
	docker run --rm --platform linux/arm64 \
		--mount type=bind,src=.,dst=/app \
		-e GENERATOR=$(GENERATOR) \
		possum:latest

docker-build:
	docker build --platform linux/arm64 \
		--file ./docker_images/possum.dockerfile . \
		-t possum

# chores

clean:
	-rm -rf .zig-cache ./zig-out build

# picotool

load:
	-picotool load -t uf2 ./zig-out/firmware.uf2 -fx

info:
	-picotool info -af
