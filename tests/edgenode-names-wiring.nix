# Called from nix/checks.nix with the per-system arguments of
# nix/shared.nix.
# The edgenode module's own names wiring, which the checks above
# only mimic by hand: an evaluated system's metrics unit, run with
# the exporter binary swapped for one that prints its arguments, so
# the shell quoting is the unit's own. Its --conductor must be
# conductorMetrics.name, and its --names file, fed with the captured
# edgenode replies through the jq the exporter runs, must name the
# apps from displayName and roleNames and expect exactly the apps
# installed = true.
{
  edgenodeNode,
  inputs,
  jqLib,
  pkgs,
  system,
  ...
}: let
  noHapp = pkgs.writeText "unused.happ" "";
  node = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      edgenodeNode
      {
        services.holochain-edgenode = {
          enable = true;
          metricsExporter.enable = true;
          conductorMetrics = {
            enable = true;
            name = "The Workshop";
          };
          happs = {
            requests-and-offers = {
              src = noHapp;
              displayName = "Requests & Offers";
              roleNames = {
                requests_and_offers = "Listings";
                hrea = "Accounting";
              };
            };
            kando.src = noHapp;
            hrea = {
              src = noHapp;
              displayName = "Accounting";
            };
            retired = {
              src = noHapp;
              installed = false;
            };
          };
        };
      }
    ];
  };
  unit = node.config.systemd.services.holochain-conductor-metrics;
in
  pkgs.runCommand "edgenode-names-wiring" {
    nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli];
  } ''
    script=${unit.serviceConfig.ExecStart}
    cat $script
    sed -E 's|^exec [^ ]*/bin/holochain-conductor-exporter |exec printf "%s\\n" |' $script > args.sh
    grep -q '^exec printf' args.sh
    bash args.sh > args
    cat args
    arg() { sed -n "/^--$1\$/{n;p;q}" args; }
    test "$(arg conductor)" = "The Workshop"
    names=$(arg names)
    jq . "$names"

    jq -e '.expected == ["hrea", "kando", "requests-and-offers"]' "$names"
    printf '%s\n%s\n%s\n' "$(cat ${./fixtures/edgenode-0_6_3/list-apps.json})" \
      "$(cat ${./fixtures/edgenode-0_6_3/dump-network-metrics.json})" "$(cat "$names")" \
      | jq -n -r -L ${jqLib} --arg conductor "$(arg conductor)" --argjson now 1790484800 \
          -f ${jqLib}/dht-metrics.jq > ws.prom
    cat ws.prom
    promtool check metrics < ws.prom
    grep -qF 'holochain_dht_info{conductor="The Workshop",app_id="requests-and-offers",role="requests_and_offers",dna="uhC0k5Kg49j1kwUFmDlTqLBXoQAZHQdutkEojX0m_OKSqBtERwBOY",app_name="Requests & Offers",app_kind="Requests & Offers",part_name="Listings",network_label="Requests & Offers: Listings"} 1' ws.prom
    grep -qF 'app_id="requests-and-offers",role="hrea",' ws.prom
    grep '^holochain_dht_info{' ws.prom | grep -F 'app_id="requests-and-offers",role="hrea",' | grep -qF 'network_label="Requests & Offers: Accounting"'
    grep -qF 'holochain_app_info{conductor="The Workshop",app_id="hrea",app_name="Accounting",app_kind="Accounting",status="enabled"} 1' ws.prom
    grep -qF 'holochain_app_info{conductor="The Workshop",app_id="kando",app_name="Kando",app_kind="Kando",status="enabled"} 1' ws.prom
    if grep -q 'retired' ws.prom; then
      echo "an app with installed = false is expected" >&2
      exit 1
    fi
    touch $out
  ''
