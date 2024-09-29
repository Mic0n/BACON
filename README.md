# BACON
![image](https://github.com/user-attachments/assets/70a04d69-ab02-4f7d-a9e0-fa59e94739dc)

The goal of this project is to create a virtual machine which uses Intel TDX protecting the confidentiality and integrity of virtual machines (Trusted Domain or TD).
Inside this TD we provide a script which allows the user to interact in a user friendly way with signed Images and Containers. The keys are stored also inside the TD.
With execution policies and multiple security checks we want to create a secure environment but still be easy to use.

The following tools will be used to accomplish the goal of this projekt:
- containerd [GitHub](https://github.com/containerd/containerd)
- nerdctl [GitHub](https://github.com/containerd/nerdctl)
- cosign [GitHub](https://github.com/sigstore/cosign)

## Motivation

BACON is a tool created to help optimize the workflow of securely using containers.
It gives an easy overview of the current state of the container host in regards to secure and measured boot.
It uses signed images to make sure the image wasn't tampered with upon pulling the image.
To prevent the user from starting containers of a high security level, when the host has been tampered with,
BACON checks if the defined policies require measured boot and tdx to be attested and executes these attestations.
Only should they be valid, the container will be started.

## Limitations

BACON cannot prevent containers with a set policy to be started by the host that signed them, even when the policy is not met, when using a different tool.
It is designed to help the legitimate operator to enforce the proper security measures. 
In order to verify Intel TDX quotes and use the remote attestation, an API Key to Intel Trust Authority is needed.
At the moment this key is not given out to end users, therefore remote attestation of the TDX quote is not currently implmented.
Should it be made available in the future, a function to generate the quote is already implemented.

## VM Setup

We used Google Cloud as our service provider. As for now an Intel TDX enabled VM can only be created using cli:
  ```
  gcloud beta compute instances create tdxvm \
    --machine-type=c3-standard-4 \
    --zone=europe-west4-a \
    --confidential-compute-type=TDX \
    --maintenance-policy=TERMINATE \
    --image-family=ubuntu-2404-lts-amd64 \
    --image-project=tdx-guest-images \
    --project=bacontdx
  ```

By default secure boot is disabled and needs also to be enabled using gcloud cli
```
    gcloud compute instances update tdxvm --shielded-secure-boot
```

## Approach

### Make sure the VM can be trusted -checking SecureBoot and TDX Attestation
- Check SecureBoot with mokutil the Command: 
  ```
  mokutil --sb-state
  ```
  It should return Secureboot enabled
  
### Getting the TDX Quote using trustauthority-cli [GitHub](https://github.com/intel/trustauthority-cli/tree/main)
- Generate sample TD Quote. Prove the Quote Generation Service is working
  ```
  trustauthority-cli quote
  ```
  the result should look like this
  ![Screenshot 2024-09-24 175335](https://github.com/user-attachments/assets/9ca01315-c951-4d20-915e-ab994f76036f)
  
- Typically the quote would be sent to Intel Trust Authority in order to Verify. This is currently not possible for end users due to intel not providing API Keys to end users
    - this would be done by configuring a config file with the right credentials eg.
      ```
        {
 	    "trustauthority_url": "https://portal.trustauthority.intel.com",
 	    "trustauthority_api_url": "https://api.trustauthority.intel.com",
 	    "trustauthority_api_key": "<Your Intel Trust Authority API Key>"
        }
      ```
    - then this command would be executed
      ```
      trustauthority-cli token -c config.json
      ```
    - the result should look like this
      ```
         22:55:17 [DEBUG] GET https://api.trustauthority.intel.com/appraisal/v1/nonce
         22:55:18 [DEBUG] POST https://api.trustauthority.intel.com/appraisal/v1/attest
         Trace Id: U5sA2GNVoAMEPkQ=
         eyJhbGciOiJQUzM4NCIsImprdSI6Imh0dHBzOi8vYW1iZXItdGVzdDEtdXNlcjEucHJvamVjdC1hbWJlci1zbWFzLmN
         .....
         .....
         .....
         DRctLIeN4MioXztymyK7qsT1p7n7Dh56-HmDQH47MVgrEL_S-wRYDQioEkUvtuA_3pGk
      ```

### Creating an image
- Create a sample Dockerfile
  ```
    cat <<EOF | tee Dockerfile.dummy
    FROM alpine:latest
    LABEL policy="Mid"
    CMD [ "echo", "Hello World" ]
    EOF
  ```
- Make sure buildctl is running
  ```
    sudo $(which buildkitd) &
  ```
- Build the image
  ```
  nerdctl build -t  [docker username]/[image name] -f Dockerfile.dummy .
  ```
### Preparing signing process
- Generate key-pair using cosign
  ```
  cosign generate-key-pair
  ```
- export the password set for key pair
  ```
    export COSIGN_PASSWORD=[password]
  ```
### Signing and pushing the image to repo
```
    nerdctl push --sign=cosign --cosign-key cosign.key [docker username]/[image name]
```
### Pulling and verifying the image using the public key
```
    nerdctl pull --verify=cosign --cosign-key cosign.pub [docker username]/[image name]
```


### Needed tools
#### tpm2-tools
- Install tpm2-tools
  ```
      apt install tpm2-tools
  ```
#### containerd
- Can be installed with apt
  ```
      sudo apt install containerd
  ```
#### nerdctl
- Can be installed with
  ```
    wget -q "https://github.com/containerd/nerdctl/releases/download/v[version]/nerdctl-full-[version]-linux-[archType].tar.gz" -O /tmp/nerdctl.tar.gz
    mkdir -p ~/.local/bin
    tar -C ~/.local/bin/ -xzf /tmp/nerdctl.tar.gz --strip-components 1 bin/nerdctl
  ```
- add nerdctl to $PATH by adding ~/.local/bin to /etc/bash.bashrc and
  ```
    source /etc/bash.bashrc
  ```
- set nerdctl user by
  ```
    sudo chown root "$(which nerdctl)"
    sudo chmod +s "$(which nerdctl)"
  ```
- now containerd can be started to test nerdctl
  ```
    sudo echo -n ; sudo containerd &
    sudo chgrp "$(id -gn)" /run/containerd/containerd.sock
    nerdctl --version
    nerdctl images
  ```
- To install the Container Network Interface - install the CNI Plugin
  ```
    tar -C ~/.local -xzf /tmp/nerdctl.tar.gz libexec
    echo 'export CNI_PATH=~/.local/libexec/cni' >> ~/.bashrc
    source ~/.bashrc
  ```
- Now the running container can be tested
  ```
    # run a test container
    nerdctl run --name dockertest --rm library/alpine:3.16.2 cat /etc/os-release

    # check if networking is working
    nerdctl run -d --name nginxtest -p 8080:80 library/nginx:1.22.1-alpine
    curl -I http://localhost:8080
    nerdctl rm -f nginxtest

    # delete test image
    nerdctl images -q | xargs nerdctl rmi
  ```
- Create a symlink
  ```
  ln -s $(which nerdctl) ~/.local/bin/docker
  ```
- In order to build images install buildkitd and buildctl
  ```
    tar -C ~/.local/bin/ -xzf /tmp/nerdctl.tar.gz --strip-components 1 bin/buildkitd bin/buildctl
  ```
- add to $PATH if needed
- start the daemon (preferrebly using tmux to not be locked to screen)
  ```
  sudo $(which buildkitd) &
  ```
- test building an image
  ```
    >Dockerfile cat <<EOF
    FROM library/alpine:3.16.2

    RUN echo hello > /tmp/hello.txt
    EOF
    nerdctl build -t myimage .
    nerdctl run --rm myimage cat /tmp/hello.txt
    nerdctl rmi myimage:latest
  ```
#### Go
- download go using apt
  ```
    apt install golang-go
  ```
- add go to $PATH if needed
#### Cosign
- install cosign using go
  ```
    go install github.com/sigstore/cosign/v2/cmd/cosign@latest
  ```
- add to $PATH if needed

If a command is not found be sure in all cases to read the individual installation guide.
In most cases you need to add an additional path to your $PATH variable.
  
  
## Showcase
The showcase demonstrates how easy it is to pull an image and start a container.
Three different policy levels are available:
- High
- Mid
- Low

You are only able to start a container if your policy level is equal or higher than the containers policy level.
E.g. if your security level is mid and container is low you can start the container.
If your security level is mid and container is high you are unable to start the container.
![showcase](https://github.com/user-attachments/assets/6a12f4d7-9799-459d-8168-710588eb1295)






