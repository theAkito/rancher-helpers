# Rancher's little helpers

Mainly consisting of helper scripts and other little tools for the management of Rancher, Kubernetes & related utilities.

### Rancher Cleanup script
#### To be clear: this DELETES EVERYTHING related to Rancher and Kubernetes!

Cleans up Rancher with Kubernetes *entirely*.
After running this script you are able to set up Rancher entirely from scratch without any complaints about remains from the previous installation.

##### Usage
```bash
bash cleanup_rancher.sh
```