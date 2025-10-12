# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY --chmod=0755 build_files /
COPY /sys_files /sys_files

# Base Image
FROM ghcr.io/ublue-os/bazzite:stable

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

That single-line command is not a valid RUN instruction for a standard Dockerfile or similar container build processes (like BuildKit in its typical configuration) because of the way the line breaks, comments, and multiple shell commands are structured.

Here's a breakdown of why it won't work as written and how to fix it:

❌ Why the Command Fails
Newlines and RUN: A RUN instruction in a Dockerfile is typically executed as a single shell command. To include multiple lines or commands, you must use the shell's continuation character (\) at the end of each line except the last one, or join them with the && operator. As written, the command stops after the first line break:

Dockerfile

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
The build system will likely see everything after this as a new, invalid instruction or ignore it, causing the build to fail or execute only the first part.

Shell Comment Placement: The shell comment (# this is a file not a directory currently) is on a new line after the first RUN line and is not escaped by a backslash (\), so it's treated as a separate, invalid Dockerfile instruction, or part of a command that's already terminated.

✅ How to Make it Work
You need to combine all the shell commands onto a single logical line using && and escape the newlines with \. The comments should either be placed before the RUN instruction or included inside the shell command string using # appropriately.

Here is the corrected and valid format:

Dockerfile

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    rm /opt && \
    mkdir /opt && \
    /ctx/build.sh && \
    /ctx/optfix.sh

# /opt is symlinked to /var/opt
# for packages that require it to be writeable do the following:
# rm /opt this is a file not a directory currently
# mkdir /opt create the opt directory so files can be installed to it
# install package (dnf5 -y install .....)
# mv /opt /usr/share/factory move files installed to /opt to /usr/share/factory so they will be in the final image
# ln -s /var/opt /opt restore symlink between /var/opt and /opt again

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
