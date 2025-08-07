# BUILD_FROM_IMAGE definition MUST be the first (uncommented) line: https://stackoverflow.com/a/78364729
ARG BUILD_FROM_IMAGE=ghcr.io/ublue-os/bazzite:stable
# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM $BUILD_FROM_IMAGE

# Build args
ARG BUILD_SHELL

# Layer on my own customizations
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh && \
    ostree container commit
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
