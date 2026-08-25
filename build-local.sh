sudo podman build --build-arg BASE_IMAGE=ghcr.io/blue-build/base-images/fedora-base:latest -t pigeon-os . && \
sudo bootc switch --transport containers-storage localhost/pigeon-os:latest
