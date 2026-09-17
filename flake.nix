{
  description = "evm_signer_cli — the headless approver for keystore_module, driven over logosctl.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    keystore_module = {
      url = "github:logos-co/logos-evm-keystore-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    # OPTIONAL. Named so the generated client exists; never loaded on its account, and
    # absent is a normal state — the interpretation it feeds is a feature, not a
    # precondition, and this signer must come up on a device that has no token list.
    token_list_module = {
      url = "github:logos-co/logos-evm-token-list-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ self, logos-module-builder, ... }:
    let
      nixpkgs = logos-module-builder.inputs.nixpkgs;
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      # x86_64-windows is a cross PSEUDO-SYSTEM the builder understands; a target, never a
      # host nixpkgs is evaluated for natively, so it only ever belongs in `packages`.
      targets = systems ++ [ "x86_64-windows" ];

      # ONE module, answered for every target at once — mkLogosModule already keys its
      # own outputs by system, so calling it inside a genAttrs evaluates the same module
      # once per target and throws all but one away.
      module = logos-module-builder.lib.mkLogosModule {
        src = ./.;
        configFile = ./metadata.json;
        flakeInputs = inputs;
      };

      # ── WHY THIS MODULE NEEDS MOBILE KEYS (#245) ──────────────────────────────
      #
      # `keystore_module` signs nothing without a human: a wallet asks through
      # `request_approval`, and only a CONFIGURED APPROVER may claim the request and
      # answer `approve(handle, bundle_id, password)`. On a desktop that approver is
      # `evm_signer_ui`. On a phone there was none at all, so the wallet UI's shield
      # route parked at its `sign` leg for ever and its `wrap` / `approve` / `shield`
      # legs had never reached a chain.
      #
      # A phone's Bundled set is resolved out of a catalog whose every entry points at
      # a module's own `mobile.<target>.bare`, so a module with no mobile output cannot
      # be in that set however well it builds on a desktop — the same absence that kept
      # `fee_module` out until #183. These keys are the whole of the port: the crate is
      # `serde` + `serde_json` + the offline tx decoder, it opens no socket and holds no
      # C dependency, and its one outbound call goes to `keystore_module` by name.
      #
      # `? ${t}` rather than a bare index, so a logos-module-builder pin without the
      # mobile cross sets leaves this flake simply WITHOUT mobile keys instead of
      # failing to evaluate.
      mobileTargets = builtins.filter (t: module.packages ? ${t})
        [ "aarch64-ios" "aarch64-ios-simulator" "aarch64-android" ];
    in
    {
      packages = nixpkgs.lib.genAttrs (targets ++ mobileTargets)
        (target: module.packages.${target});

      # An Android cross derivation's `system` is its BUILD platform, so
      # `packages.aarch64-android` is pinned to the builder's canonical one
      # (x86_64-linux) and a Mac cannot realise it. The same artifact, reached from
      # whichever machine is doing the building:
      #   nix build .#legacyPackages.aarch64-darwin.mobile.aarch64-android.bare
      legacyPackages = module.legacyPackages or { };

      # THE MODULE'S OWN ANSWER ABOUT ITSELF, forwarded so a consumer flake can read it
      # without building anything. logos-basecamp's mobile catalog takes this module's
      # `version` and its `dependencies` from here rather than restating them: a Bundled
      # set resolves a CLOSURE out of the catalog entry, and a hand-copied list in a
      # SIGNED manifest is a claim the core would act on after it had drifted.
      #
      # WHAT THE CLOSURE FINDS HERE, and it is the one thing to get right: the only
      # declared dependency is `keystore_module`, which reaches a phone as a `web`
      # variant in the image's web assets and NEVER as a Bundled Bare module (one vault,
      # one module — the catalog says why at `railgun_module`). ADR 0010 is what lets
      # the closure resolve it: a Bundled member may depend on a module THIS IMAGE
      # CARRIES, Bundled or `web`. `token_list_module` is an OPTIONAL dependency and is
      # deliberately not in `dependencies`, so a `--bundle evm_signer_cli` does not drag
      # a token list onto a device that has no use for one.
      inherit (module) config configFor;
    };
}
