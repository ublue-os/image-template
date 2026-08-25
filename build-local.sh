sudo podman build --build-arg BASE_IMAGE=quay.io/fedora/fedora-kinoite -t pigeon-os . && \
sudo bootc switch --transport containers-storage localhost/pigeon-os:latest
sudo reboot
