#!/bin/bash

set -ouex pipefail

if [[ BUILD_CITRIX -eq "1" ]]; then
    # I'm checking for a checksum match, because I don't trust this script - too many assumption built-in
    CHECKSUM="7aca51455f546de3da31ce8961fee8b3edc5b6e2e8804e1c445ff836f35df549"
    VERSION="25.05.0.44-0"
    DL_TARGET=/tmp/citrix_workspace_x86_64.rpm
    # Scrape website to get the right download link
    url=$(wget -O - https://www.citrix.com/downloads/workspace-app/linux/workspace-app-for-linux-latest.html | sed -ne '/ICAClient-rhel.*/ s/<a .* rel="\(.*\)" id="downloadcomponent.*">/https:\1/p' | sed -e 's/\r//g')
    DL_VERSION=$(echo ${url} | grep -Po 'rhel-.*.rpm' | sed 's/rhel-//g' | sed 's/.x86_64.rpm//g')
    # Download the file
    wget ${url} -O ${DL_TARGET}
    DL_CHECKSUM=$(sha256sum ${DL_TARGET} | awk '{print $1}')
    if [[ "${CHECKSUM}" == "${DL_CHECKSUM}" ]]; then
        mkdir -p /var/opt # /opt is a symlink to /var/opt, but it doesn't exist in the base image. Check for possible downstream issues.
        dnf5 install -y ${DL_TARGET}
    else
        echo "Checksum does not match!"
        echo "Expected: ${CHECKSUM}, Found: ${DL_CHECKSUM}"
        echo "Expected: ${VERSION}, Found: ${DL_VERSION}"
        exit 1
    fi
fi
