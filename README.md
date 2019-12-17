# Rancher's little helpers

Copied
[![Build Status](https://drone.akito.ooo:52222/api/badges/Akito/rancher-helpers/status.svg)](https://drone.akito.ooo:52222/Akito/rancher-helpers)

Mainly consisting of helper scripts and other little tools for the management of Rancher and Kubernetes.

### Rancher Cleanup script
#### To be clear: this DELETES EVERYTHING related to Rancher and Kubernetes!

Cleans up Rancher with Kubernetes *entirely*.
After running this script you are able to set up Rancher entirely from scratch without any complaints about remains from the previous installation.

##### Usage
```bash
bash cleanup_rancher.sh
```