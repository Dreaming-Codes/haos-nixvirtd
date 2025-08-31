{
  description = "Home Assistant OS VM via nixvirt";

  nixConfig = {
    extra-substituters = [
      "https://cache.garnix.io"
    ];
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };

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
    nixosModules.home-assistant-vm = {
      lib,
      pkgs,
      config,
      ...
    }: let
      inherit (lib) mkIf mkOption mkEnableOption types;
      cfg = config.virtualisation.home-assistant-vm;
    in {
      imports = [nixvirt.nixosModules.libvirt];

      options.virtualisation.home-assistant-vm = {
        enable = mkEnableOption "Home Assistant OS VM";
        memoryGiB = mkOption {
          type = types.ints.positive;
          default = 8;
          description = "RAM for the VM in GiB.";
        };
      };

      config = mkIf cfg.enable {
        virtualisation.libvirtd = {
          enable = true;
          qemu = {
            package = pkgs.qemu_kvm;
            ovmf.enable = true;
          };
        };

        virtualisation.libvirt.connections."qemu:///system".domains = [
          {
            autostart = true;
            definition =
              nixvirt.lib.domain.writeXML
              (nixvirt.lib.domain.templates.linux {
                name = "Home-Assistant";
                uuid = "cc7439ed-36af-4696-a6f2-1f0c4474d87e";
                uefi = true;
                memory = {
                  count = cfg.memoryGiB;
                  unit = "GiB";
                };
                storage_vol = {
                  pool = "default";
                  volume = "Home-Assistant.qcow2";
                };
                backing_vol = haosBase;
              });
          }
        ];
      };
    };

    packages.${system}.haos-base = haosBase;
  };
}
