all:
	@just -l

[group('docker')]
run:
	docker run --rm --platform linux/arm64 --mount type=bind,src=.,dst=/app possum:latest

[group('docker')]
run-clean: clean
	docker run --rm --platform linux/arm64 --mount type=bind,src=.,dst=/app possum:latest

[group('docker')]
build:
	docker build --platform linux/arm64 --file ./docker_images/possum.dockerfile . -t possum

[group('docker')]
clean:
  -rm -rf .zig-cache ./zig-out build

[group('picotool')]
load:
  -picotool load -t uf2 ./zig-out/firmware.uf2 -fx

[group('picotool')]
info:
	-picotool info -af
