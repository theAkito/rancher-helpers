#!/bin/bash
#########################################################################
# Copyright (C) 2019-2020 Akito <the@akito.ooo>                         #
#                                                                       #
# This program is free software: you can redistribute it and/or modify  #
# it under the terms of the GNU General Public License as published by  #
# the Free Software Foundation, either version 3 of the License, or     #
# (at your option) any later version.                                   #
#                                                                       #
# This program is distributed in the hope that it will be useful,       #
# but WITHOUT ANY WARRANTY; without even the implied warranty of        #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the          #
# GNU General Public License for more details.                          #
#                                                                       #
# You should have received a copy of the GNU General Public License     #
# along with this program. If not, see <http://www.gnu.org/licenses/>.  #
#########################################################################
# Based on
# https://github.com/rancher/rancher/issues/19882#issuecomment-501056386

## Cleans up Rancher with Kubernetes *entirely*.
## After running this script you are able to
## set up Rancher entirely from scratch
## without any complaints about remains
## from the previous installation.

## Run as root!
## Only works reliably with GNU Bash.
## Expects `systemd` on the host.

#################################   Boilerplate of the Boilerplate   ####################################################
# Coloured Echoes                                                                                                       #
function red_echo      { echo -e "\033[31m$@\033[0m";   }                                                               #
function green_echo    { echo -e "\033[32m$@\033[0m";   }                                                               #
function yellow_echo   { echo -e "\033[33m$@\033[0m";   }                                                               #
function white_echo    { echo -e "\033[1;37m$@\033[0m"; }                                                               #
# Coloured Printfs                                                                                                      #
function red_printf    { printf "\033[31m$@\033[0m";    }                                                               #
function green_printf  { printf "\033[32m$@\033[0m";    }                                                               #
function yellow_printf { printf "\033[33m$@\033[0m";    }                                                               #
function white_printf  { printf "\033[1;37m$@\033[0m";  }                                                               #
# Debugging Outputs                                                                                                     #
function white_brackets { local args="$@"; white_printf "["; printf "${args}"; white_printf "]"; }                      #
function echoDebug  { local args="$@"; if [[ ${debug_flag} == true ]]; then                                             #
white_brackets "$(white_printf   "DEBUG")" && echo " ${args}"; fi; }                                                    #
function echoInfo   { local args="$@"; white_brackets "$(green_printf  "INFO" )"  && echo " ${args}"; }                 #
function echoWarn   { local args="$@"; white_brackets "$(yellow_printf "WARN" )"  && echo " ${args}"; 1>&2; }           #
function echoError  { local args="$@"; white_brackets "$(red_printf    "ERROR")"  && echo " ${args}"; 1>&2; }           #
# Silences commands' STDOUT as well as STDERR.                                                                          #
function silence { local args="$@"; ${args} &>/dev/null; }                                                              #
# Check your privilege.                                                                                                 #
function checkPriv { if [[ "$EUID" != 0 ]]; then echoError "Please run me as root."; exit 1; fi;  }                     #
# Returns 0 if script is sourced, returns 1 if script is run in a subshell.                                             #
function checkSrc { (return 0 2>/dev/null); if [[ "$?" == 0 ]]; then return 0; else return 1; fi; }                     #
# Prints directory the script is run from. Useful for local imports of BASH modules.                                    #
# This only works if this function is defined in the actual script. So copy pasting is needed.                          #
function whereAmI { printf "$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )";   }                     #
# Alternatively, this alias works in the sourcing script, but you need to enable alias expansion.                       #
alias whereIsMe='printf "$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"'                            #
debug_flag=false                                                                                                        #
#########################################################################################################################
function containerd_restart { silence "systemctl restart containerd"; }
function rmMetaDB { silence "rm -f /var/lib/containerd/io.containerd.metadata.v1.bolt/meta.db"; }
function docker_start { silence "systemctl start docker"; }
function docker_stop { silence "systemctl stop docker"; }
function finish_line { white_printf "OK\n"; }
function checkSys {
  ## Makes sure that script is not accidentally run on wrong target system.
  ## Exits if Docker is not installed.
  silence "docker version"
  if [[ $? == 0 ]]; then
    echoInfo "Docker exists."
    return 0
  else
    echoError "Docker not installed/running on system. Exiting."
    exit 1
  fi
}
function docker_restart {
  docker_stop
  echoInfo "Restarting Docker..."
  sleep 10;
  docker_start
  if [[ $? == 0 ]]; then
    echoInfo "Docker restarted!"
    return 0
  else
    echoError "Docker restart failed!"
    white_printf "Manually stop docker then wait 20 seconds and start it again.\n"
    exit 1
  fi
}
function rmContainers {
  ## Removes ALL containers.
  silence "docker rm -f $(docker ps -aq)" && \
  echoInfo "Successfully removed all Docker containers." || \
  echoInfo "No Docker containers exist! Skipping."
}
function rmVolumes {
  ## Removes ALL volumes.
  silence "docker volume rm $(docker volume ls -q)" && \
  echoInfo "Successfully removed all Docker volumes." || \
  echoInfo "No Docker volumes exist! Skipping."
}
function rmLocs {
  ## Removes all Rancher and Kubernetes related folders.
  declare -a FOLDERS
  FOLDERS=( "/etc/ceph" \
            "/etc/cni" \
            "/etc/kubernetes" \
            "/opt/cni" \
            "/opt/rke" \
            "/run/secrets/kubernetes.io" \
            "/run/calico" \
            "/run/flannel" \
            "/var/lib/calico" \
            "/var/lib/weave" \
            "/var/lib/etcd" \
            "/var/lib/cni" \
            "/var/lib/kubelet" \
            "/var/lib/rancher/rke/log" \
            "/var/log/containers" \
            "/var/log/pods" \
            "/var/run/calico" \
          )
  for loc in "${FOLDERS[@]}"; do
    if [ -d ${loc} ]; then
      timeout 15s rm -fr ${loc} || \
        { \
         echoError   "Timed out while trying to remove ${loc}."
         yellow_echo "Run \"rm -fr ${loc}\" manually."
         exit 2
        }
      echoInfo "${loc} successfully deleted."
    else
      echoInfo "${loc} not found! Skipping."
    fi
  done
  ## Removes Rancher installation from default installation directory.
  local rancher_loc="/opt/rancher"
  if [ -d ${rancher_loc} ]; then
    silence "rm -fr /opt/rancher"
    if [[ $? ]]; then
      echoInfo "Rancher successfully removed from ${rancher_loc}."
    else
      echoError "Rancher could not be removed from ${rancher_loc}!"
    fi
  else
    echoInfo "Rancher not found in ${rancher_loc}! Skipping."
  fi
  ## Removes .kube folder in all personal home directories.
  local -a personal_folder_list=( $(silence "find /home/* -maxdepth 0 -type d" || true) )
  local kube_folder
  for dir in ${personal_folder_list[@]}; do
    kube_folder="${dir}/.kube"
    silence "rm -fr ${kube_folder}"
    if [[ $? ]]; then
      echoInfo "${kube_folder} successfully removed."
    elif [[ -d ${kube_folder} ]]; then
      echoError "${kube_folder} could not be removed!"
    else
      echoInfo "${kube_folder} not found! Skipping."
    fi
  done
}
function cleanFirewall {
  ## Removes Firewall entries related to Rancher or Kubernetes.
  IPTABLES="/sbin/iptables"
  cat /proc/net/ip_tables_names | while read table; do
    $IPTABLES -t $table -L -n | while read c chain rest; do
        if test "X$c" = "XChain" ; then
          silence "$IPTABLES -t $table -F $chain"
          if [[ $? ]]; then
            echoInfo  "Chain ${chain} from Table ${table} successfully flushed."
          else
            echoError "Chain ${chain} from Table ${table} could not be flushed!"
          fi
        fi
    done
    silence "$IPTABLES -t $table -X"
    if [[ $? ]]; then
      echoInfo  "Chains from Table ${table} successfully removed."
    else
      echoError "Chains from Table ${table} could not be removed!"
    fi
  done
}
function extractVolName {
  ## Extracts volume ID.
  # Volume path.
  local vol="$1"
  # Resulting volume ID.
  local vol_id
  # Removes everything after first dash from original string.
  local split_string1="$(printf '%s' "${vol%%-*}")"
  # Removes everything before first dash from original string.
  local split_string2="$(printf '%s' "${vol#*-}")"
  # Removes everything before last slash from split_string1.
  split_string1="$(printf '%s' "${split_string1##*/}")"
  # Removes everything after first slash from split_string2.
  split_string2="$(printf '%s' "${split_string2%%/*}")"
  # Combines both cleaned split_strings, resulting in the volume ID.
  vol_id="$(printf '%s' "${split_string1}-${split_string2}")"
  # Print volume ID.
  printf '%s\n' "${vol_id}"
}
function rmDevs {
  ## Unmounts all Rancher and Kubernetes related virtual devices and volumes.
  ## Unmounts all Persistent Volume Claims, forcefully.
  local -a mount_list=( $(mount | grep -E '/var/lib/kubelet[[:print:]]*tmpfs' | awk '{ print $3 }') )
  for mount in "${mount_list[@]}" /var/lib/kubelet /var/lib/rancher; do
    silence "umount -f ${mount}"
    if [[ $? ]]; then
      if [[ "${mount}" == "/var/lib/kubelet" ]] || [[ "${mount}" == "/var/lib/rancher" ]]; then
        echoInfo  "${mount} successfully unmounted."
      else
        echoInfo  "$(extractVolName "${mount}") successfully unmounted."
      fi
    else
      echoError "${mount} could not be unmounted."
    fi
  done
}
function rmNetworkInterfaces {
   ## Removes Network Interfaces created by Kubernetes and Rancher.
  function getNetIfaces {
    ## Gets a list of Network Interfaces created by Kubernetes and Rancher.
    local iface
    local ifaces="$(ls /sys/class/net)"
    local pattern='flannel.1|cni0|tunl0|cali[[:alnum:]]{11}|veth[[:alnum:]]{7,8}'
    for iface in $ifaces; do
      if [[ ${iface} =~ ${pattern} ]]; then
        printf '%s ' ${iface}
      fi
    done
  }
  local -a iface_list=( $(getNetIfaces) )
  for iface in ${iface_list[@]}; do
    silence "ip link delete ${iface}"
    if [[ $? ]]; then
      echoInfo "${iface} successfully removed!"
    else
      echoInfo "${iface} could not be removed."
    fi
  done
  unset -f getNetIfaces
}
############################################
############################################
# Checks if user running the script is root.
checkPriv
# Makes sure that script is not accidentally run on wrong target system.
# Exits if Docker is not installed.
checkSys
# Removes ALL containers.
rmContainers
# Removes ALL volumes.
rmVolumes
# Unmounts all Rancher and Kubernetes related virtual devices and volumes.
rmDevs
# Removes all Rancher and Kubernetes related folders.
# Removes Rancher installation from default installation directory.
rmLocs
# Removes metadata database.
rmMetaDB
# Removes Firewall entries related to Rancher or Kubernetes.
cleanFirewall
# Removes Network Interfaces created by Kubernetes and Rancher.
rmNetworkInterfaces
# Restarts services, to apply previous removals.
containerd_restart
# Slowed down Docker restart. Needs a pause, because else it complains about "too quick" restarts.
docker_restart
# Process finished.
finish_line

