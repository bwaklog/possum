all:
	@echo "make [run|build|clean]"

run:
	docker run --rm --platform linux/arm64 --mount type=bind,src=.,dst=/app possum:latest

run-clean: clean
	docker run --rm --platform linux/arm64 --mount type=bind,src=.,dst=/app possum:latest

build:
	docker build --platform linux/arm64 --file ./docker_images/possum.dockerfile . -t possum

clean:
	-rm -rf .zig-cache ./zig-out build

load:
	-picotool load -t uf2 ./zig-out/firmware.uf2 -fx

info:
	-picotool info -af
