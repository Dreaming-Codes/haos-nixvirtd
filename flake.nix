{
  description = "Home Assistant OS VM via nixvirt";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixvirt = {
      url = "https://flakehub.com/f/AshleyYakeley/NixVirt/*.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixvirt,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};

    haosVersion = "16.1";
    haosUrl = "https://github.com/home-assistant/operating-system/releases/download/${haosVersion}/haos_ova-${haosVersion}.qcow2.xz";

    haosXz = pkgs.fetchurl {
      url = haosUrl;
      hash = "sha256-93ESB9nvj+B9i2hTpIoU+m3Yf5X/YRnAMXy7uWhRz6U=";
    };

    haosBase =
      pkgs.runCommand "haos-${haosVersion}.qcow2"
      {buildInputs = [pkgs.xz];} ''
        unxz -c ${haosXz} > $out
      '';
  in {
    # Reusable module: imports nixvirt and defines the VM
    nixosModules.home-assistant-vm = {pkgs, ...}: {
      imports = [nixvirt.nixosModules.libvirt];

      virtualisation.libvirtd = {
        enable = true;
        qemu = {
          package = pkgs.qemu_kvm;
          ovmf.enable = true;
        };
      };

      # Define the VM on qemu:///system
      virtualisation.libvirt.connections."qemu:///system".domains = [
        {
          autostart = true;

          definition =
            nixvirt.lib.domain.writeXML
            (nixvirt.lib.domain.templates.linux {
              name = "Home-Assistant";
              uuid = "cc7439ed-36af-4696-a6f2-1f0c4474d87e";
              memory = {
                count = 8;
                unit = "GiB";
              };
              # You can add `vcpu = 2;` if you want more/less CPUs
              uefi = true;

              # Create an overlay in the default pool backed by the HAOS base image
              storage_vol = {
                pool = "default";
                volume = "Home-Assistant.qcow2";
              };
              backing_vol = haosBase;
            });
        }
      ];
    };

    # Example host config using the module (optional)
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit nixvirt;};
      modules = [
        self.nixosModules.home-assistant-vm
        ({...}: {
          networking.hostName = "host";
        })
      ];
    };

    # Expose decompressed base image (optional)
    packages.${system}.haos-base = haosBase;
  };
}
