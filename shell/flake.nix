{
  description = "CTP Shell Development Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-24.11";
  };

  outputs = { self, nixpkgs }: 
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Base image configuration
      baseImage = pkgs.dockerTools.pullImage {
        imageName = "rockylinux";
        imageDigest = "sha256:2d05a9266523bbf24f33ebc3a9832e4d5fd74b973c220f2204ca802286aa275d";
        sha256 = "sha256-ZAF9TuP1t3gRz6/k6WBkmQHEkU4K+tKcQMFwlPxRo4c=";
        finalImageTag = "8.9.20231119";
      };
     
      # Package groups
      # basePackages = with pkgs; [
      #   coreutils
      #   shadow
      #   sudo
      #   openssh
      #   which
      # ];

      devPackages = with pkgs; [
        gcc
        gnumake
        binutils
        git
        vim
        openjdk8-bootstrap
      ];

      utilPackages = with pkgs; [
        lsof
        procps
        file
        wget
        dos2unix
        lcov
        bc
        expect
        nettools
      ];

      # Setup commands
      setupCommands = ''
        # Setup entrypoint
        cp ${./docker-entrypoint.sh} entrypoint.sh
        chmod 775 entrypoint.sh
      '';

    in {
      packages.${system} = {
        docker-image = pkgs.dockerTools.buildLayeredImage {
          name = "ctp_shell";
          tag = "latest";
          fromImage = baseImage;
          # contents = basePackages ++ devPackages ++ utilPackages;
          contents = devPackages ++ utilPackages;
          # maxLayers = 50;

          config = {
            Cmd = [ "/entrypoint.sh" ];
            WorkingDir = "/";
            # ExposedPorts."8080/tcp" = {};
            Env = [
              "JAVA_HOME=/usr/lib/jvm/java-1.8.0"
              "CTP_BRANCH_NAME=develop"
              "CTP_SKIP_UPDATE=0"
              "TZ=Asia/Seoul"
              "LANG=en_US.UTF-8"
              "LC_ALL=en_US.UTF-8"
            ];
          };

          extraCommands = setupCommands;
        };

        default = self.packages.${system}.docker-image;
      };
    };
}

