# possum

> A operating system built for Raspberry Pi Pico

## Requirement

- [Docker](https://www.docker.com/)
- [Make](https://www.gnu.org/software/make/manual/make.html) (or [just](https://just.systems/))
- (add dependencies to build on bare metal here)

## Building the project

### Using docker
- build the image

```sh
make run

# optionally use just
just run
```

- Run the container with the `run-clean` recipe if you are cleaning the '.zig-cache' and 'cmake' builds
