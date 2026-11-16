{
  inputs,
  self,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    shared,
    ...
  }: let
    inherit (shared) bootstrapTest dinoAdventureHapp edgenodeNode fixtureTextfiles happTest holochainRulesFile jqLib kandoHapp metricsChecks metricsTest monitor on06 onX86 servicesTest smokeTest;
    args = shared;
  in {
    checks = {
      # Every exported nixosModule evaluates in a minimal system
      # (tests/nixos-modules-eval.nix).
      nixosModulesEval = import ../tests/nixos-modules-eval.nix args;
      # The publication guard: no new lab name, LAN address or secret
      # in a tracked file, and an allowlist that only shrinks (tests/public-guard.nix).
      publicGuard = import ../tests/public-guard.nix args;
      edgenodeBinaryCache = import ../tests/edgenode-binary-cache.nix args;
      edgenodeConfigRender = import ../tests/edgenode-config-render.nix args;
      conductorMetricsJq = import ../tests/conductor-metrics-jq.nix args;
      dhtMetricsJq = import ../tests/dht-metrics-jq.nix args;
      # The whole exporter, run for an edgenode-shaped and a Moss-shaped
      # conductor on captured replies (tests/metrics.nix): the two files
      # declare every shared family with the same bytes and a real
      # node_exporter keeps both, and no name a dashboard shows is a hash.
      inherit (metricsChecks) metricsHelpAgreement metricsNameShape;
      # The provisioned dashboards, with no VM (tests/dashboards.nix): no
      # label but a human one reaches a legend, a display name, a table
      # column or a stat's field, no text shows a variable holding a key,
      # every panel is described and every uid is its own; every stand-in
      # value (1e9, an empty cell) reads as its word in its colour; and
      # every Holochain query of every dashboard answers, through the rule
      # file, on the homelab's two conductors plus a clone cell, the node
      # reading its worst conductor, with every series it reads there and
      # every rule it names recorded. Each is also run on broken input and
      # must then fail.
      inherit
        (import ../tests/dashboards.nix {
          inherit pkgs jqLib;
          rules = holochainRulesFile;
          inherit (metricsChecks) runs;
        })
        dashboardLabels
        dashboardWords
        dashboardQueries
        ;
      # The recording rules every dashboard reads, under promtool's rule
      # tests: a node alone, nodes in step and catching up, contact lost
      # three ways, readings that stop, the homelab's two conductors from
      # the exporter's jq on the captured replies, an app expected and not listed, DHTs
      # with no name, node states, conductors under the default name, a
      # machine in trouble and a healthy one. Each
      # expectation is also broken on its own and must then fail.
      holochainRules = import ../tests/rules.nix {
        inherit pkgs;
        rules = holochainRulesFile;
        overviewRulesFor = units: builtins.head (monitor [{services.holochain-grafana.overviewUnits = units;}]).services.prometheus.ruleFiles;
        textfiles = fixtureTextfiles;
      };
      # What the grafana module renders, from evaluated systems: node and
      # site labels per scrape target, the refusal of two targets sharing
      # a node name, the rule file with non-default states, and the
      # dashboard rewrite (units, unit names, room constants).
      grafanaProvisioning = import ../tests/provisioning.nix {
        inherit pkgs monitor;
        modules = {
          edgenode = edgenodeNode;
          inherit (self.nixosModules) holochain-http-gateway holochain-bootstrap holochain-windtunnel holochain-moss-node;
        };
      };
      edgenodeNamesWiring = import ../tests/edgenode-names-wiring.nix args;
      vmTestAdminPlane = import ../tests/admin-plane-vm.nix args;
      # What grafana.cookieSecure and duckdns render, evaluated
      # (tests/admin-plane.nix).
      adminPlaneOptions = import ../tests/admin-plane.nix {
        inherit pkgs;
        nixos-holochain = self;
      };
      vmTestGrafana = import ../tests/grafana-vm.nix args;
      vmTestWindtunnel = import ../tests/windtunnel-vm.nix args;
      vmTestGateway = import ../tests/gateway-vm.nix args;
      vmTest = smokeTest {
        name = "holochain-edgenode-smoke";
        line = "0.7";
      };
      vmTest-0_6 = smokeTest {
        name = "holochain-edgenode-smoke-0_6";
        line = "0.6";
        nodeExtra = on06;
      };
      vmTestWithHapp = happTest {
        name = "holochain-edgenode-happ-installer";
        line = "0.7";
        appId = "dino-adventure";
        happ = dinoAdventureHapp;
      };
      # The 0.7 line's gauges are covered end to end by vmTestGrafana; this
      # is the 0.6 half of "both lines produce it".
      vmTestConductorMetrics-0_6 = metricsTest {
        name = "holochain-conductor-metrics-0_6";
        nodeExtra = on06;
      };
      # Two 0.6 edgenodes find each other through a holochain-bootstrap
      # server with no internet, over its plain-HTTP relay.
      vmTestBootstrap = bootstrapTest {name = "holochain-bootstrap";};
      # Every service the enabled modules install, on the node page by
      # its name, derived from the configuration: with the bootstrap
      # server and the HTTP gateway, then without the server.
      vmTestServices = servicesTest {name = "holochain-services";};
      vmTestServices-noBootstrap = servicesTest {
        name = "holochain-services-no-bootstrap";
        bootstrap = false;
      };
      vmTestWithHapp-0_6 = happTest {
        name = "holochain-edgenode-happ-installer-0_6";
        line = "0.6";
        appId = "kando";
        happ = kandoHapp;
        nodeExtra = on06;
      };
      ${onX86 "vmTestHoloportInstall"} = import ../tests/holoport-install-vm.nix args;
    };
  };
}
