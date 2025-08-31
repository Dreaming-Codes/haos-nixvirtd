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
      options.virtualisation.home-assistant-vm = {
        enable = mkEnableOption "Home Assistant OS VM";
        memoryGiB = mkOption {
          type = types.ints.positive;
          default = 8;
          description = "RAM for the VM in GiB.";
        };
        active = mkOption {
          type = types.bool;
          default = true;
          description = "Wether to start the vm";
        };
        pool = mkOption {
          type = types.str;
          default = "default";
          description = "Pool to use for storage";
        };
        volume = mkOption {
          type = types.str;
          default = "Home-Assistant.qcow2";
          description = "Volume to use for storage";
        };
        network = mkOption {
          type = types.str;
          default = "virbr0";
          description = "Network to use for the vm";
        };
      };

      config = mkIf cfg.enable {
        virtualisation.libvirt.connections."qemu:///system" = {
          domains = [
            {
              active = cfg.active;
              definition =
                nixvirt.lib.domain.writeXML
                (nixvirt.lib.domain.templates.linux {
                  name = "Home-Assistant";
                  uuid = "f753eeab-1317-4812-8a1d-00c479a4c67f";
                  uefi = true;
                  bridge_name = cfg.network;
                  memory = {
                    count = cfg.memoryGiB;
                    unit = "GiB";
                  };
                  storage_vol = {
                    pool = cfg.pool;
                    volume = cfg.volume;
                  };
                  backing_vol = {
                    path = haosBase;
                    format = {type = "qcow2";};
                  };
                  channels = [
                    {
                      type = "unix";
                      target = {
                        type = "virtio";
                        name = "org.qemu.guest_agent.0";
                      };
                    }
                  ];
                });
            }
          ];
        };
      };
    };

    packages.${system}.haos-base = haosBase;
  };
}
