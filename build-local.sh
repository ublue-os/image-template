sudo podman build --build-arg BASE_IMAGE=ghcr.io/ublue-os/bazzite:stable -t pigeon-os . && \
sudo bootc switch --transport containers-storage localhost/pigeon-os:latest
sudo reboot
