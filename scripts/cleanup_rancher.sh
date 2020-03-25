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
function echoInfo   { local args="$@"; white_brackets $(green_printf "INFO") && echo " ${args}"; }                      #
function echoWarn   { local args="$@";  echo "$(white_brackets "$(yellow_printf "WARN")" && echo " ${args}";)" 1>&2; }  #
function echoError  { local args="$@"; echo "$(white_brackets "$(red_printf    "ERROR")" && echo " ${args}";)" 1>&2; }  #
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
            "/var/lib/etcd" \
            "/var/lib/cni" \
            "/var/lib/kubelet" \
            "/var/lib/rancher/rke/log" \
            "/var/log/containers" \
            "/var/log/pods" \
            "/var/run/calico" \
            "/home/$1/.kube" \
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
  fail_rloc=false
  local rancher_loc="/opt/rancher"
  if [ -d ${rancher_loc} ]; then
    silence "rm -fr /opt/rancher"
    if [[ $? ]]; then
      echoInfo "Rancher successfully removed from ${rancher_loc}."
    else
      echoError "Rancher could not be removed from ${rancher_loc}!"
      fail_rloc=true
    fi
  else
    echoInfo "Rancher not found in ${rancher_loc}! Skipping."
  fi
}
function cleanFirewall {
  ## Removes Firewall entries related to Rancher or Kubernetes.
  IPTABLES="/sbin/iptables"
  cat /proc/net/ip_tables_names | while read table; do
    silence "$IPTABLES -t $table -L -n" | while read c chain rest; do
        if test "X$c" = "XChain" ; then
          silence "$IPTABLES -t $table -F $chain"
        fi
    done
    silence "$IPTABLES -t $table -X"
  done
  echoInfo "Firewall rules cleared."
}
function rmDevs {
  ## Unmounts all Rancher and Kubernetes related virtual devices and volumes.
  fail_mount=false
  fail_pvc=false
  local -a mount_list=( $(mount | grep tmpfs | grep '/var/lib/kubelet' | awk '{ print $3 }') )
  for mount in "${mount_list[@]}" /var/lib/kubelet /var/lib/rancher; do
    silence "umount -f ${mount}"
    if [[ $? ]]; then
      echoInfo  "${mount} successfully unmounted."
    else
      echoError "${mount} could not be unmounted."
      fail_mount=true
    fi
  done
  ## Unmounts all Persistent Volume Claims, forcefully.
  local -a pvc_list=( $(mount | grep '/var/lib/kubelet/pods' | awk '{ print $3 }') )
  for pvc in "${pvc_list[@]}"; do
    silence "umount -f ${pvc}"
    if [[ $? ]]; then
      echoInfo  "$(printf ${pvc} | cut -c 1-45)... successfully unmounted."
    else
      echoError "${pvc} could not be unmounted."
      fail_pvc=true
    fi
  done
}
function fazit {
  ## Checks for fail flags set during other processes and
  ## outputs a summary of possible errors.
  local -i err_counter=0
  if   [[  $fail_mount == true ]]; then
    let "err_counter++"
  fi
  if   [[  $fail_pvc == true ]]; then
    let "err_counter++"
  fi
  if   [[  $fail_rloc == true ]]; then
    let "err_counter++"
  fi
}
############################################
############################################
currentuser=$1

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
rmLocs "$currentuser"
# Removes metadata database.
rmMetaDB
# Removes Firewall entries related to Rancher or Kubernetes.
cleanFirewall
# Restarts services, to apply previous removals.
containerd_restart
# Slowed down Docker restart. Needs a pause, because else it complains about "too quick" restarts.
docker_restart
# Checks for fail flags set during other processes and outputs a summary of possible errors.
fazit
# Process finished.
finish_line

