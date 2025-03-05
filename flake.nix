{
  description = "Ruby Dev Env";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell/main";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };
  outputs =
    { self
    , nixpkgs
    , flake-utils
    , devshell
    , flake-compat
    , ...
    }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      cwd = builtins.toString ./.;
      overlays = map (x: x.overlays.default) [
        devshell
      ];
      pkgs = import nixpkgs { inherit system overlays; };
      runtimeDependencies = with pkgs; [
        graphviz
        inkscape
        jre
        plantuml
        xml2rfc
      ];
    in
    rec {

      # nix develop
      devShell = pkgs.devshell.mkShell {

        env = [
        ];
        commands = [
          {
            name = "metanorma";
            command = "exe/metanorma \"$@\"";
            help = "Run Metanorma CLI";
            category = "App";
          }
          {
            name = "release";
            command = "bundle exec rake release \"$@\"";
            help = "Run rake release, which adds a tag and pushes to RubyGems";
            category = "Ruby";
          }
          {
            name = "lint";
            command = "bundle exec rubocop \"$@\"";
            help = "Run rubocop";
            category = "Ruby";
          }
          {
            name = "update-flakes";
            command = "make update-flakes \"$@\"";
            help = "Update all flakes";
            category = "Nix";
          }
        ] ++
        # Only append these if there is no .tool-verions file
        # to avoid conflicts:
        (if ! builtins.pathExists ./.tool-versions then
          [{

            name = "irb";
            command = "bundle exec irb \"$@\"";
            help = "Run console IRB (has completion menu)";
            category = "Ruby";
          }
            {
              name = "console";
              command = "bundle exec irb \"$@\"";
              help = "Run console IRB (has completion menu)";
              category = "Ruby";
            }
            {
              name = "pry";
              command = "bundle exec pry \"$@\"";
              help = "Run pry";
              category = "Ruby";
            }
            {
              name = "rspec";
              command = "bundle exec rspec \"$@\"";
              help = "Run test suite";
              category = "Ruby";
            }]
        else [ ]);

        packages = with pkgs; [
          # rubocop                  # Install with your Gemfile / gemspec
          # ruby                     # Install with your favourite Ruby version manager, etc.
          # rubyPackages.solargraph  # Bring your own
          # rubyfmt                  # Broken
          bash
          curl
          fd
          fzf
          gnused
          jq
          ripgrep
          rubyPackages.ruby-lsp
          rubyPackages.sorbet-runtime
          wget
          pkg-config # for building native extensions
        ] ++
        runtimeDependencies;

      };
    });
}
