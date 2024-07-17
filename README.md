# Scripts for running phoronix-test-suite in a VM

This is the hot pile of stinking garbage I've used to benchmark upstream ASI. It
runs the FIO benchmark from Phoronix Test Suite on a QEMU guest on an Ubuntu
24.04 host. It takes care of installing the kernel and gathering results.

It was mostly tested without a root login on the target host but towards the end
I switched to a machine where I have direct root SSH access. If you're running
without root login, and you hit some permissions errors, try adding `become:
true` to the relevant stanza in host-setup.yaml.

To use it, something like:

- Get a machine running Ubuntu 24.04 that you can SSH into.

  At one point I did this using GCE bare metal, and in that case I created it
  something like this:

  ```sh
  gcloud compute instances create $HOST_INSTANCE --zone=us-east4-c --machine-type=c3-standard-192-metal  --maintenance-policy=TERMINATE --create-disk=boot=true,image-family=ubuntu-2404-lts-amd64,image-project=ubuntu-os-cloud,size=128 --metadata=enable-oslogin=true
  ```

  After a while I started using a different system which made more interesting
  CPUs available.

- Build your kernel as a .deb pacakge. Try something like this:

  ```sh
  ssh $user@$host 'cat /boot/config-$(uname -r)' > .config && \
    scripts/config -d CONFIG_SYSTEM_TRUSTED_KEYS -d CONFIG_SYSTEM_REVOCATION_KEYS &&
    ssh $user@host lsmod > lsmod.txt && make localyesconfig LSMOD=lsmod.txt \
    make olddefconfig && make -j100 bindeb-pkg -s
  ```

  You also probably want to modify `CONFIG_CMDLINE[_BOOL]` and
  `CONFIG_LOCALVERSION` for some of these.

- Wait for it to boot and be SSHable

- Write an inventory describing the host. The group with the host instances should be called
  `host_hosts` and each host should have a variable called
  `kernel_deb_local_path` containing the kernel image and one called
  `kernel_release_string` which should be the result of running `make
  kernelrelease` when you compiled the kernel.

  ```yaml
  host_hosts:
    hosts:
      # Give each host a normal name in the inventory, dont' use raw hostnames
      # or IPs as the keys, or the upload_results script will get confused.
      my_host:
        ansible_host: 65.21.121.123
    vars:
      ansible_user: root
      kernel_deb_local_path: ~/src/linux/linux-image-6.10.0asi-00032-gb28ddf044ce9_6.10.0-00032-gb28ddf044ce9-2_amd64.deb
      kernel_release_string: 6.10.0asi-00032-gb28ddf044ce9
      # You might also want to configure SSH like this if you work in an
      # environment where SSH is complicated (like Google):
      ansible_ssh_private_key_file: ~/.ssh/id_rsa
      ansible_ssh_extra_args: '-o IdentitiesOnly=yes'
  ```

- Run `run.sh $DB_PATH`. This is currently hardcoded for my specific ASI Rome
  benchmarking needs.