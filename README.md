# ublue-custom-start

# Purpose

This repository is meant to be used as a template to build your own custom Universal Blue Image. This base template is what the Universal Blue Project uses for all of our new and existing downstream projects (Bazzite, Bluefin, and Ucore). Each project has edited from this template to suit their own individual needs for more advanced build requirements. This template includes a Containerfile and 2 Github workflows (one for building the container and one for building an installation ISO from the container file) that will work immediately out of the box as soon as you enable the workflow in your repository.

# Prerequisites

Working knowledge in the following topics:

- Containers
  - Resources:
    - https://www.youtube.com/watch?v=SnSH8Ht3MIc
    - https://www.mankier.com/5/Containerfile
- rpm-ostree
  - Resources:
    - https://coreos.github.io/rpm-ostree/
- Fedora Silverblue (and other Fedora Atomic variants)
  - Resources:
    - https://docs.fedoraproject.org/en-US/fedora-silverblue/
- Github Workflows
  - Resources:
    - https://docs.github.com/en/actions/using-workflows

# How to Use

## Template

Since this is a template repository, you can select `Use this Template` and create a new repository from it. To enable the workflows, you will need to go the actions tab of the new repository and enable the workflows.

## Containerfile

This is the main file used to customize the base image you are using. There are several examples of how to add layered rpm-ostree packages

## Workflows
The `build.yml` workflow creates your OCI container
