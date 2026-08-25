sudo podman build --build-arg BASE_IMAGE=quay.io/fedora/fedora-kinoite:44 -t pigeon-os . && \
sudo bootc switch --transport containers-storage localhost/pigeon-os:latest
