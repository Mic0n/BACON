#!/bin/bash

main() {
  declare -r SCRIPTPATH=$(readlink -f "${0}")
  declare -r SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
  declare -r UWAIT=0

  ### System
  declare -r VERBASH="${BASH_VERSION}"
  declare -r VERSTATION="v0.1"
  declare -r KERNELVERS="$(uname -r)"
  declare -r PID=$$

  # Color
  declare -r RED='\033[0;31m'
  declare -r NC='\033[0m'

  ### Info
  printf "###System Info###"
  printf "\nScript Version: ${VERSTATION}"
  printf "\nBash-Version: ${VERBASH}"
  printf "\nKernel-Version: ${KERNELVERS}"
  printf "\nCurrent Directory: ${SCRIPTDIR}"
  printf "\nPID: ${PID}"
  printf "\nCurrent time: $(date "+%YY-%mM-%dD_%Hh:%Mm:%Ss")\n"

  ### Check Requirements
  commandsCheck

  # Trust Domain Extensions (TDX) Driver Check
  tdx=/dev/tdx_guest
  if [ -e "$tdx" ]; then
    echo "$tdx exists."
  else
    echo "TDX guest driver not found."
    exit 1
  fi

  # Platform Configuration Registers (PCR) Check
  declare -r PCR_KNOWNGOOD=${SCRIPTDIR}/.pcr_values
  checkMeasured

  # Secure Boot Status
  if [[ $(mokutil --sb-state) == "SecureBoot disabled" ]]; then
    declare -r SecureBootStatus="disabled"
  else
    declare -r SecureBootStatus="enabled"
  fi

  # Check for key pair. If not exist, create.
  declare COSIGN_PASSWORD
  cosignpriv=${SCRIPTDIR}/cosign.key
  cosignpub=${SCRIPTDIR}/cosign.pub
  [ -f "$cosignpub" -a -f "$cosignpriv" ] && echo -e "Found cosign.key $cosignpriv \nFound cosign.pub $cosignpub!" || genKey

  # Check log-in
  checkLogin

  # Set Policy
  declare runtimepolicy
  setPolicy

  while true; do
    serviceLogin
  done
}

function serviceLogin() {
  while true; do
    clear
    printf "Docker Station Running."
    printf "\nSecureboot Status: [${SecureBootStatus}]"
    printf "\nPolicy Level: [${runtimepolicy}]"
    read -p "$(printf "\n$RED[L]]$NC\bIST Images | $RED[B]]$NC\bUILD Image | $RED[P]]$NC\bUSH Image | P$RED[U]]$NC\bLL Image | R$RED[E]]$NC\bMOVE Images \n$RED[R]]$NC\bUNNING Containers | $RED[S]]$NC\bTART Container | S$RED[T]]$NC\bOP Container | PRU$RED[N]]$NC\bE Container \n$RED[C]]$NC\bHANGE Policy | $RED[G]]$NC\bET Sample TD Quote \nE$RED[X]]$NC\bIT \nPress $RED<ENTER>>$NC\b: ")" userChoice
    case $userChoice in
    [Ll])
      printf 'List Images. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      executeServiceList
      break
      ;;
    [Bb])
      printf 'Build an Image. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      executeServiceBuild
      break
      ;;
    [Rr])
      printf 'Running Containers. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      executeServiceRunning
      break
      ;;
    [Pp])
      printf 'Push Image. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      executeServicePUSH
      break
      ;;
    [Uu])
      printf 'Pull Image. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      executeServicePULL
      break
      ;;
    [Ee])
      printf 'Remove Images. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      executeServiceREMOVE
      break
      ;;
    [Ss])
      printf 'Start Container. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      executeServiceSTART
      break
      ;;
    [Tt])
      printf 'Stop Container. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      executeServiceSTOP
      break
      ;;
    [Nn])
      printf 'Prune Containers. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      executeServicePRUNE
      break
      ;;
    [Cc])
      printf 'Change Policy. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      setPolicy
      break
      ;;
    [Gg])
      printf 'Generate sample Quote. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      executeServiceQUOTE
      break
      ;;
    [Xx])
      printf 'Quitting program. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      exit
      break
      ;;
    *)
      printf 'Input %s is not valid. Retry in %s seconds...\n' "${userChoice}" "${UWAIT}"
      sleep ${UWAIT}
      ;;
    esac
  done

}

executeServiceList() {
  echo -e "Execute nerdctl images"
  nerdctl images
  read -p "Press enter to continue"
}

executeServiceBuild() {
  echo -e "Start buildkitd if needed"
  sudo $(which buildkitd) &
  read -p "Enter docker username: " dockeruser
  read -p "Enter image name: " imagename
  read -p "Enter Dockerfile: " dockerfile
  read -p "Enter Path: " path

  echo -e "Command to execute: nerdctl build -t $dockeruser/$imagename -f $dockerfile $path"
  read -p "Continue (y/n)?" userchoice
  case "$userchoice" in
  [Yy])
    nerdctl build -t $dockeruser/$imagename -f $dockerfile $path
    sleep ${UWAIT}
    return
    ;;
  [Nn])
    echo -e "Return to main menu"
    sleep ${UWAIT}
    return
    ;;
  *)
    echo -e "Invalid. Return to main menu"
    sleep ${UWAIT}
    return
    ;;
  esac
}

executeServiceRunning() {
  echo -e "Execute nerdctl ps"
  nerdctl ps
  read -p "Press enter to continue"
}

executeServicePUSH() {
  if [ -z "${COSIGN_PASSWORD}" ]; then
    read -p "Enter cosign key password " password
  fi
  echo -e "List all images"
  nerdctl images
  read -p "Enter docker username: " dockeruser
  read -p "Enter image name: " imagename

  echo -e "Command to execute: nerdctl push --sign=cosign --cosign-key $cosignpriv $dockeruser/$imagename"
  read -p "Continue (y/n)?" userchoice
  case "$userchoice" in
  [Yy])
    COSIGN_PASSWORD=$password nerdctl push --sign=cosign --cosign-key $cosignpriv $dockeruser/$imagename
    sleep ${UWAIT}
    return
    ;;
  [Nn])
    echo -e "Return to main menu"
    sleep ${UWAIT}
    return
    ;;
  *)
    echo -e "Invalid. Return to main menu"
    sleep ${UWAIT}
    return
    ;;
  esac
}

executeServicePULL() {
  read -p "Enter docker username: " dockeruser
  read -p "Enter image name: " imagename

  echo -e "Command to execute: nerdctl pull --verify=cosign --cosign-key $cosignpub $dockeruser/$imagename"
  read -p "Continue (y/n)?" userchoice
  case "$userchoice" in
  [Yy])
    nerdctl pull --verify=cosign --cosign-key $cosignpub $dockeruser/$imagename
    sleep ${UWAIT}
    return
    ;;
  [Nn])
    echo -e "Return to main menu"
    sleep ${UWAIT}
    return
    ;;
  *)
    echo -e "Invalid. Return to main menu"
    sleep ${UWAIT}
    return
    ;;
  esac
}

executeServiceREMOVE() {
  read -p "Do you also want to remove all unused images, not just dangling ones (y/n)?" userchoice
  case "$userchoice" in
  [Yy])
    nerdctl image prune --all
    sleep ${UWAIT}
    return
    ;;
  [Nn])
    nerdctl image prune
    sleep ${UWAIT}
    return
    ;;
  *)
    echo -e "Invalid. Return to main menu"
    sleep ${UWAIT}
    return
    ;;
  esac
}

executeServiceSTART() {
  echo -e "Current policy: $runtimepolicy"
  echo -e "Listing Images. Please select:"
  nerdctl images --names
  read -p "Enter Image name " imagename
  echo -e "Inspecting Image"
  local imagepolicy=$(nerdctl image inspect --format '{{ index .Config.Labels "policy"}}' $imagename)

  case $imagepolicy in
  High)

    checkPolicy $imagepolicy && nerdctl run -d $imagename || echo error
    ;;
  Mid)
    checkPolicy $imagepolicy && nerdctl run -d $imagename || echo error
    ;;
  Low)
    checkPolicy $imagepolicy && nerdctl run -d $imagename || echo error
    ;;
  *)
    echo -e "Unknown Policy: [$imagepolicy]"
    echo -e "Return to main menu"
    sleep 2
    return
    ;;
  esac
}

executeServiceSTOP() {
  echo -e "List of running containers"
  nerdctl ps
  read -p "Please enter Container ID " containerid
  nerdctl stop $containerid
  echo -e "Container with ID $containerid has been stopped."
  echo -e "Returning to main menu."
  sleep ${UWAIT}
}

executeServicePRUNE() {
  nerdctl container prune
  echo -e "Returning to main menu."
  sleep ${UWAIT}
}

executeServiceQUOTE() {
  echo -e "Generate sample TD Quote. Prove the Quote Generation Service is working"
  echo -e "Execute trustauthority-cli quote"
  sudo trustauthority-cli quote
  read -p "Press enter to continue"
}

# Usage: Check if user is root
isRoot() {
  [ $(id -u) -eq 0 ]
}

checkLogin() {
  # Check if login exist
  FILE=~/.docker/config.json
  if ! test -f "$FILE"; then
    echo -e "$FILE does not exists"
    echo -e "Please login using 'nerdctl login -u <USERNAME>'"
    echo -e "Further information: https://github.com/containerd/nerdctl/blob/main/docs/registry.md#docker-hub"
    echo -e "Quitting..."
    exit 1
  else
    echo -e "Found Image registry information $FILE"
  fi
}

genKey() {
  while true; do
    clear
    echo -e "Either cosign.key or cosign.pub is missing!"
    echo -e "WARNING: Create a new key pair WILL delete cosign.key and cosign.pub if they exist."
    read -p "$(printf "\n$RED[C]]$NC\bREATE New Keys | E$RED[X]]$NC\bIT \nPress $RED<ENTER>>$NC\b: ")" userChoice
    case $userChoice in
    [Cc])
      printf 'Generate key pair Containers. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      rm $cosignpub 2>/dev/null
      rm $cosignpriv 2>/dev/null
      cd $SCRIPTDIR && cosign generate-key-pair
      echo "New key pair has been created! Please Restart Script. Exit now."
      exit 1
      break
      ;;
    [Xx])
      printf 'Quitting program. Progress in %s seconds...\n' "${UWAIT}"
      sleep ${UWAIT}
      exit 1
      break
      ;;
    *)
      printf 'Input %s is not valid. Retry in %s seconds...\n' "${userChoice}" "${UWAIT}"
      sleep ${UWAIT}
      ;;
    esac
  done
}

# Input: 1. image policy
checkPolicy() {
  local policyToCheck="$1"
  # If image is High, System needs be High
  # If image is Mid, System needs be Mid or High
  # If image is Low, System needs be Mid or High or Low

  echo -e "Selected Image policy is: [$imagepolicy]"
  echo -e "System policy is: [$runtimepolicy]"
  case $policyToCheck in
  High)
    # only ok if system is also high
    if [ $runtimepolicy = "High" ]; then
      echo -e "Image policy qualifies to execute. Starting Container."
      true
    else
      echo -e "System Policy is higher than Image policy. Unable to start."
      false
    fi
    ;;
  Mid)
    if [ $runtimepolicy = "High" ] || [ $runtimepolicy = "Mid" ]; then
      echo -e "Image policy qualifies to execute. Starting Container."
      true
    else
      echo -e "System Policy is higher than Image policy. Unable to start."
      false
    fi
    ;;
  Low)
    if [ $runtimepolicy = "High" ] || [ $runtimepolicy = "Mid" ] || [ $runtimepolicy = "Low" ]; then
      echo -e "Image policy qualifies to execute. Starting Container."
      true
    else
      echo -e "System Policy is higher than Image policy. Unable to start."
      false
    fi
    ;;
  *)
    echo -e "Unknown Policy to check: [$policyToCheck]"
    echo -e "Unknown error. Return to main menu"
    false
    return
    ;;
  esac
}

setPolicy() {
  echo -e "Change of policy will stop all containers."
  PS3='Please enter your security level: '
  options=("High" "Mid" "Low" "Exit")
  select opt in "${options[@]}"; do
    case $opt in
    "High")
      echo -e "High choosen"
      runtimepolicy=High
      sleep $UWAIT
      break
      ;;
    "Mid")
      echo -e "Mid choosen"
      runtimepolicy=Mid
      break
      ;;
    "Low")
      echo -e "Low choosen"
      runtimepolicy=Low
      break
      ;;
    "Exit")
      exit
      break
      ;;
    *) echo -e "invalid option $REPLY" ;;
    esac
  done

  echo -e "Stopping all running containers..."
  nerdctl ps -q | xargs nerdctl stop 2>/dev/null
  echo -e "All running containers have been stopped. Continue..."
  sleep ${UWAIT}
}

checkMeasured() {

  if [ -f "$PCR_KNOWNGOOD" ] && [ -r "$PCR_KNOWNGOOD" ]; then
    echo -e "Known good is available"
    new_quote=$(sudo tpm2_pcrread)
    known_good=$(<$PCR_KNOWNGOOD)

    if [ "$new_quote" = "$known_good" ]; then
      echo -e "Measured Boot attested."
    else
      echo -e "Measured Boot Attestation failed. Do you want to reset the known good? [y]es [n]o"
      read -n 1 key # Reads one character without requiring Enter

      if [ "$key" = "y" ]; then
        setKnownGood
      else
        echo -e "Measured Boot couldnt be validated. Exiting"
        exit 1
      fi
    fi
  else
    echo -e "File $PCR_KNOWNGOOD either does not exist or is not readable. Do you want to set the known good? [y]es [n]o"
    read -n 1 key

    if [ "$key" = "y" ]; then
      setKnownGood
    else
      echo -e "Measured Boot couldnt be validated. Exiting"
      exit 1
    fi
  fi
}

setKnownGood() {
  sudo tpm2_pcrread >$PCR_KNOWNGOOD
  checkMeasured
}

commandsCheck() {
  if ! command -v cosign 2>&1 >/dev/null; then
    echo -e "cosign could not be found"
    exit 1
  else
    echo -e "cosign found at $(which cosign)"
  fi

  if ! command -v tpm2_pcrread 2>&1 >/dev/null; then
    echo -e "tpm2_pcrread could not be found"
    exit 1
  else
    echo -e "tpm2_pcrread found at $(which tpm2_pcrread)"
  fi

  if ! command -v mokutil 2>&1 >/dev/null; then
    echo -e "mokutil could not be found. Unable to check Secureboot Status"
    exit 1
  else
    echo -e "mokutil found at $(which mokutil)"
  fi

  if ! command -v nerdctl 2>&1 >/dev/null; then
    echo -e "nerdctl could not be found"
    exit 1
  else
    echo -e "nerdctl found at $(which cosign)"
  fi
}

### Entrypoint.
main "${@}"
exit
