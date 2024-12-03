# Scripts for running phoronix-test-suite in a VM

This is the hot pile of stinking garbage I've used to benchmark upstream ASI. It
runs the FIO benchmark from Phoronix Test Suite on a QEMU guest on a Debian host
build by [`mkosi`](https://github.com/systemd/mkosi), using a
[PiKVM](https://docs.pikvm.org/) attached to a random desktop sitting in my
office. I believe with minimal tweaking it should work in basically any context
with x86 UEFI. It currently requires the test machine to have access to the
internet; with more work (but not _that_ much more) it should be possible to
make it work without internet access (as long as you can SSH to the box).

## Usage:

- Once: build the phoronix-test-suite container image:
  ```
  podman build -t pts pts-container/
  podman save --format oci-archive -o pts-container/pts.oci pts
  ```
- Set these environment variables:

  ```
  export PIKVM_PASSWORD=<Web UI password for your Pi-KVM>
  export PIKVM_HOST=<domain name/IP of your Pi-KVM>
  export PIKVM_HTTPS_PORT=8080
  export PIKVM_SSH_USER=<user you can SSH to the Pi as>
  export PIKVM_SSH_PORT=2223
  export HOST=<domain name/IP of the host you're gonna run teh tests on>
  export HOST_SSH_PORT=2222
  ```

- Figure out what drivers are needed to boot on your host. The easiest way to do
  this is to boot up a normal system on it, run `lsmod`, then copy that to your
  kernel tree and use `make localyesconfig` to enable all the drivers that were
  loaded.

  You [probably also
  want](https://unix.stackexchange.com/questions/537912/nftables-rule-no-such-file-or-directory-error)
  `CONFIG_NFT_COUNTER`, `CONFIG_NFT_OBJREF` and `CONFIG_NF_TABLES_INET` for
  libvirt networking to work.

  Other generally useful cmdlines for benchmarking:
    - `CONFIG_LOCALVERSION_AUTO` so you know exactly what kernel code you're testing
    - `CONFIG_IKCONFIG`  and `CONFIG_IKCONFIG_PROC` so you know the kernel config.

- Build your kernel as a `bzImage`, copy it to
  `./mkosi/mkosi.extra/usr/lib/modules/$(make kernelrelease)/vmlinuz` in this
  repo.
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
      # You might also want to configure SSH like this if you work in an
      # environment where SSH is complicated (like Google):
      ansible_ssh_private_key_file: ~/.ssh/id_rsa
      ansible_ssh_extra_args: '-o IdentitiesOnly=yes'
      ansible_ssh_port: 2222
  ```

- Run `run.sh $DB_PATH`. This is currently hardcoded for my specific ASI Rome
  benchmarking needs. Extra args are passed through to `mkosi` so you might want
  `--kernel-command-line-extra=something`.

  Watch out because this overrides the whole cmdline, which means you can lose
  stuff that is needed for the QEMU boot to work. Workarounds for that are:

  - Use `--kernel-command-line-extra`.. but that won't have any effect on HW. Or:
  - Boot up a VM and copy-paste the commandline, then use that as the base of
    your `--kernel-command-line` argument. For me it was like this:

    ```
     --kernel-command-line="initrd=\debian\initrd initrd=\debian\6.12.0-00057-ga91a0599bdb7\kernel-modules.initrd systemd.mount-extra=LABEL=scratch:/var/tmp:ext4 rw systemd.wants=network.target module_blacklist=vmw_vmci systemd.tty.term.hvc0=tmux-256color systemd.tty.columns.hvc0=139 systemd.tty.rows.hvc0=71 ip=enc0:any ip=enp0s1:any ip=enp0s2:any ip=host0:any ip=none loglevel=4 SYSTEMD_SULOGIN_FORCE=1 systemd.tty.term.console=tmux-256color systemd.tty.columns.console=139 systemd.tty.rows.console=71 console=hvc0 TERM=tmux-256color"
    ```

  This might benefit from some engagement with the mkosi folkd.


## Historical notes for my future self

In prior iterations it was also tested on an Ubuntu 24.04 image, using a) GCE
bare metal and b) a Hetzner dedicated server. GCE worked pretty well except that
the firmware boots really slowly. I abandoned this because I didn't want to get
locked into a platform where I was likely to suddently find I needed to test on
a CPU that wasn't supported.

This was how I created the GCE bare metal instances:

```sh
gcloud compute instances create $HOST_INSTANCE --zone=us-east4-c --machine-type=c3-standard-192-metal  --maintenance-policy=TERMINATE --create-disk=boot=true,image-family=ubuntu-2404-lts-amd64,image-project=ubuntu-os-cloud,size=128 --metadata=enable-oslogin=true
```

Next I used Hetzner Dedicated for a while which is a slightly less "modern"
experience (unlike GCE bare metal which is more or less just GCE, except the
instance is a physical host). IIRC the main downside of Hetzner was that most of
their machines don't give you a serial port. IIRC it's possible to get a video
stream if the machine suports it, but it's not immediate (I think a DC tech
needs to go and plug it in at your request). The process of recovering from a
borked machine is also slightly arduous. On balance, it's probably about equal
to the Pi-KVM in terms of schleppiness and sketchiness. The only reason I
abandoned Hetzner in the end was Google bureaucracy getting in the way.

Earlier versions of this tooling were using stock Ubuntu images, building the
kernel as a .deb, and installing and rebooting into it using Ansible. This was
super annoying, I never really got the Grub config right so it would often
reboot into the wrong kernel. It's also pretty annoying to build .debs.