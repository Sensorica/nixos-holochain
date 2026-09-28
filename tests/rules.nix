# promtool rule tests for modules/holochain-rules.nix, on the rule file the
# grafana module renders with its default states: one case per shape a node
# can be in, and the homelab's own shape, two conductors on one instance, from
# what the exporter's jq writes for the captured replies.
#
# Every expectation is then broken on purpose, one at a time, and promtool
# must fail on each: a test that cannot fail proves nothing.
#
# The clock: promtool starts every case at time 0 and steps one minute at a
# time, so a timestamp series of "0+60x60" is always fresh, and a constant
# one goes stale.
{
  pkgs,
  # The rendered rule file.
  rules,
  # The two fixture conductors' textfiles (tests/fixture-textfiles.nix).
  textfiles,
}: let
  inherit (pkgs) lib;

  job = "holochain-nodes";
  labels = attrs: "{" + lib.concatStringsSep ", " (lib.mapAttrsToList (k: v: ''${k}="${v}"'') attrs) + "}";
  series = name: attrs: values: {
    series = name + labels attrs;
    inherit values;
  };
  # A value held for the whole case.
  hold = v: "${toString v}+0x60";
  fresh = "0+60x60";

  target = node: {
    instance = "${node}:9100";
    inherit job node;
  };

  up = node: value: series "up" (target node) (hold value);

  # node_exporter's series for one unit in one state, one filesystem (its
  # size is 100, so `avail` is its free percentage) and one sensor.
  unitState = at: name: state: value:
    series "node_systemd_unit_state" (at
      // {
        inherit name state;
        type = "simple";
      }) (hold value);
  disk = at: device: fstype: mountpoint: avail: let
    fs = at // {inherit device fstype mountpoint;};
  in [
    (series "node_filesystem_avail_bytes" fs (hold avail))
    (series "node_filesystem_size_bytes" fs (hold 100))
  ];
  temperature = at: value:
    series "node_hwmon_temp_celsius" (at
      // {
        chip = "platform_coretemp_0";
        sensor = "temp1";
      }) (hold value);

  conductor = {
    node,
    name ? "Workshop",
    isUp ? 1,
    stamp ? fresh,
  }: let
    at = target node // {conductor = name;};
  in [
    (series "holochain_conductor_up" at (hold isUp))
    (series "holochain_conductor_metrics_scrape_timestamp_seconds" at stamp)
  ];

  # One DHT: its data series and, when it has a name, its info row.
  dht = {
    node,
    conductor ? "Workshop",
    app,
    role ? app,
    dna,
    peers,
    local,
    peer ? hold 0,
    gossip ? hold (-1),
    name ? null,
  }: let
    key =
      target node
      // {
        inherit conductor role dna;
        app_id = app;
      };
  in
    [
      (series "holochain_dht_peers" key peers)
      (series "holochain_dht_local_ops" key local)
      (series "holochain_dht_peer_ops" key peer)
      (series "holochain_dht_seconds_since_gossip" key gossip)
    ]
    ++ lib.optional (name != null) (series "holochain_dht_info" (key
      // {
        app_name = name;
        app_kind = name;
        part_name = "";
        network_label = name;
      }) (hold 1));

  app = {
    node,
    conductor ? "Workshop",
    app,
    name,
    status ? "enabled",
  }:
    series "holochain_app_info" (target node
      // {
        inherit conductor status;
        app_id = app;
        app_name = name;
        app_kind = name;
      }) (hold 1);

  expect = expr: eval_time: samples: {
    inherit expr eval_time;
    exp_samples = samples;
  };
  sample = attrs: value: {
    labels = labels attrs;
    inherit value;
  };
  # A sample of a recorded series, which keeps its name.
  recorded = name: attrs: value: {
    labels = name + labels attrs;
    inherit value;
  };

  dhtStates = "max by (node, app_id, role) (holochain:dht_state)";
  appStates = "max by (node, app_name) (holochain:app_state:named)";
  nodeStates = "max by (node) (holochain:node_state)";

  cases = [
    {
      name = "a node alone: No one else yet";
      input_series =
        [(up "lab-1" 1)]
        ++ conductor {node = "lab-1";}
        ++ dht {
          node = "lab-1";
          app = "kando";
          dna = "dnaK";
          peers = hold 0;
          local = hold 7;
          name = "Kando";
        }
        ++ [
          (app {
            node = "lab-1";
            app = "kando";
            name = "Kando";
          })
        ];
      promql_expr_test = [
        (expect dhtStates "30m" [
          (sample {
              node = "lab-1";
              app_id = "kando";
              role = "kando";
            }
            3)
        ])
        (expect appStates "30m" [
          (sample {
              node = "lab-1";
              app_name = "Kando";
            }
            3)
        ])
        (expect "max by (node, conductor) (holochain:conductor_state)" "30m" [
          (sample {
              node = "lab-1";
              conductor = "Workshop";
            }
            3)
        ])
        (expect "holochain:node_state" "30m" [(recorded "holochain:node_state" (target "lab-1") 3)])
        (expect "holochain:dht_share" "30m" [])
        (expect "max by (network_label) (holochain:dht_heard:named)" "30m" [(sample {network_label = "Kando";} 1.0e9)])
        (expect "holochain:dna_nodes" "30m" [(recorded "holochain:dna_nodes" {dna = "dnaK";} 1)])
        (expect "holochain:dna_same_data" "30m" [])
        (expect "holochain:node_problem" "30m" [])
      ];
    }

    {
      name = "three nodes on one network: In step and Catching up";
      input_series =
        lib.concatMap (node: [(up node 1)] ++ conductor {inherit node;}) ["lab-1" "lab-2" "lab-3"]
        ++ lib.concatMap ({
          node,
          local,
        }:
          dht {
            inherit node;
            app = "ro";
            dna = "dnaR";
            peers = hold 2;
            local = hold local;
            peer = hold 199;
            gossip = hold 20;
            name = "Requests & Offers";
          }) [
          # 193/200 of the best peer's data: in step.
          {
            node = "lab-1";
            local = 192;
          }
          {
            node = "lab-2";
            local = 199;
          }
          # 180/200: catching up.
          {
            node = "lab-3";
            local = 179;
          }
        ];
      promql_expr_test = [
        (expect dhtStates "30m" (map (node:
          sample {
            inherit node;
            app_id = "ro";
            role = "ro";
          } (
            if node == "lab-3"
            then 4
            else 5
          )) ["lab-1" "lab-2" "lab-3"]))
        (expect "holochain:dna_nodes" "30m" [(recorded "holochain:dna_nodes" {dna = "dnaR";} 3)])
        (expect "holochain:dna_same_data" "30m" [(recorded "holochain:dna_same_data" {dna = "dnaR";} 0.9)])
        (expect ''max by (node) (holochain:dht_missing:named{node="lab-3"})'' "30m" [(sample {node = "lab-3";} 20)])
        (expect nodeStates "30m" (map (node: sample {inherit node;} 3) ["lab-1" "lab-2" "lab-3"]))
      ];
    }

    {
      name = "a node that had peers and has none: Lost contact";
      input_series =
        [(up "lab-1" 1)]
        ++ conductor {node = "lab-1";}
        ++ dht {
          node = "lab-1";
          app = "kando";
          dna = "dnaK";
          peers = "1x10 0x50";
          local = hold 50;
          peer = "50x10 0x50";
          gossip = "5+60x60";
          name = "Kando";
        };
      promql_expr_test = [
        (expect dhtStates "5m" [
          (sample {
              node = "lab-1";
              app_id = "kando";
              role = "kando";
            }
            5)
        ])
        (expect dhtStates "30m" [
          (sample {
              node = "lab-1";
              app_id = "kando";
              role = "kando";
            }
            2)
        ])
      ];
    }

    {
      name = "a DNA another node runs, with no peer here: Lost contact";
      input_series =
        lib.concatMap (node: [(up node 1)] ++ conductor {inherit node;}) ["lab-1" "lab-2"]
        ++ dht {
          node = "lab-1";
          app = "ro";
          dna = "dnaR";
          peers = hold 0;
          local = hold 7;
          name = "Requests & Offers";
        }
        ++ dht {
          node = "lab-2";
          app = "ro";
          dna = "dnaR";
          peers = hold 1;
          local = hold 10;
          peer = hold 10;
          gossip = hold 30;
          name = "Requests & Offers";
        };
      promql_expr_test = [
        (expect dhtStates "30m" [
          (sample {
              node = "lab-1";
              app_id = "ro";
              role = "ro";
            }
            2)
          (sample {
              node = "lab-2";
              app_id = "ro";
              role = "ro";
            }
            5)
        ])
      ];
    }

    {
      name = "peers known and nothing heard: Lost contact";
      input_series =
        [(up "lab-1" 1)]
        ++ conductor {node = "lab-1";}
        ++ lib.concatMap ({
          role,
          gossip,
        }:
          dht {
            node = "lab-1";
            app = "notes";
            inherit role;
            dna = "dna-${role}";
            peers = hold 1;
            local = hold 10;
            peer = hold 10;
            gossip = hold gossip;
            name = "Notes ${role}";
          }) [
          {
            role = "silent";
            gossip = 700;
          }
          {
            role = "never";
            gossip = -1;
          }
          {
            role = "talking";
            gossip = 500;
          }
        ];
      promql_expr_test = [
        (expect "max by (role) (holochain:dht_state)" "30m" [
          (sample {role = "silent";} 2)
          (sample {role = "never";} 2)
          (sample {role = "talking";} 5)
        ])
        (expect "max by (network_label) (holochain:dht_heard:named)" "30m" [
          (sample {network_label = "Notes silent";} 700)
          (sample {network_label = "Notes never";} 1.0e9)
          (sample {network_label = "Notes talking";} 500)
        ])
      ];
    }

    {
      name = "readings that stop: No fresh readings";
      input_series =
        [(up "lab-1" 1)]
        # The exporter's last file stays put after ten minutes.
        ++ conductor {
          node = "lab-1";
          stamp = "0+60x10 600x50";
        }
        ++ dht {
          node = "lab-1";
          app = "kando";
          dna = "dnaK";
          peers = hold 0;
          local = hold 7;
          name = "Kando";
        };
      promql_expr_test = [
        (expect dhtStates "5m" [
          (sample {
              node = "lab-1";
              app_id = "kando";
              role = "kando";
            }
            3)
        ])
        (expect dhtStates "30m" [
          (sample {
              node = "lab-1";
              app_id = "kando";
              role = "kando";
            }
            1)
        ])
        (expect "max by (conductor) (holochain:conductor_state)" "30m" [(sample {conductor = "Workshop";} 2)])
        (expect nodeStates "30m" [(sample {node = "lab-1";} 2)])
        (expect "holochain:node_problem" "30m" [
          (recorded "holochain:node_problem" {
              instance = "lab-1:9100";
              node = "lab-1";
              conductor = "Workshop";
              problem = "Holochain (Workshop) readings are over 90 s old";
            }
            0)
        ])
      ];
    }

    {
      # The input series are the exporter's own output, added at build time.
      name = "the homelab: Workshop and Moss on one instance";
      input_series = [];
      promql_expr_test = [
        (expect ''max by (conductor, network_label) (holochain:dht_state:named)'' "5m" (lib.mapAttrsToList (label: value:
          sample {
            conductor = builtins.head (lib.splitString "/" label);
            network_label = builtins.elemAt (lib.splitString "/" label) 1;
          }
          value) {
          # One chat has a peer and holds nearly all of its data; the other
          # has nobody and never had, which is normal for a tool nobody else
          # opened. The group holds 948 of 975 items: in step.
          "Moss/Sensorica: Members and tools" = 5;
          "Moss/Sensorica: Foyer" = 5;
          "Moss/Sensorica: Shared assets" = 5;
          "Moss/General chat: Messages" = 5;
          "Moss/General chat: Files" = 5;
          "Moss/Vines 1: Messages" = 3;
          "Moss/Vines 1: Files" = 3;
          # The edgenode conductor's apps are alone on their networks.
          "Workshop/Requests & Offers: Listings" = 3;
          "Workshop/Requests & Offers: Accounting" = 3;
          "Workshop/Kando" = 3;
          "Workshop/Hrea" = 3;
        }))
        (expect "count(holochain:dht_state:named)" "5m" [(sample {} 11)])
        (expect ''max by (conductor, app_name) (holochain:app_state:named)'' "5m" (lib.mapAttrsToList (label: value:
          sample {
            conductor = builtins.head (lib.splitString "/" label);
            app_name = builtins.elemAt (lib.splitString "/" label) 1;
          }
          value) {
          "Moss/Sensorica" = 5;
          "Moss/General chat" = 5;
          "Moss/Vines 1" = 3;
          "Workshop/Requests & Offers" = 3;
          "Workshop/Kando" = 3;
          "Workshop/Hrea" = 3;
        }))
        (expect "holochain:node_state" "5m" [
          (recorded "holochain:node_state" (target "homelab" // {site = "Soushi home";}) 3)
        ])
        (expect "holochain:node_problem" "5m" [])
      ];
    }

    {
      name = "an app Nix expects that Holochain does not list: Not running";
      input_series =
        [(up "lab-1" 1)]
        ++ conductor {node = "lab-1";}
        ++ dht {
          node = "lab-1";
          app = "kando";
          dna = "dnaK";
          peers = hold 0;
          local = hold 7;
          name = "Kando";
        }
        ++ [
          (app {
            node = "lab-1";
            app = "kando";
            name = "Kando";
          })
          (app {
            node = "lab-1";
            app = "hrea";
            name = "Hrea";
            status = "expected";
          })
          # Switched off on purpose: not a state at all.
          (app {
            node = "lab-1";
            app = "old";
            name = "Old";
            status = "disabled";
          })
        ];
      promql_expr_test = [
        (expect appStates "30m" [
          (sample {
              node = "lab-1";
              app_name = "Kando";
            }
            3)
          (sample {
              node = "lab-1";
              app_name = "Hrea";
            }
            0)
        ])
      ];
    }

    {
      name = "DHTs without a name: Unnamed app, parts named after their roles, and a problem";
      input_series =
        [(up "lab-1" 1)]
        ++ conductor {node = "lab-1";}
        ++ lib.concatMap ({
          role,
          dna,
        }:
          dht {
            node = "lab-1";
            app = "mystery";
            inherit role dna;
            peers = hold 0;
            local = hold 7;
          }) [
          {
            role = "rFiles";
            dna = "dnaF";
          }
          {
            role = "requests_and_offers";
            dna = "dnaR";
          }
        ];
      promql_expr_test = [
        (expect "holochain:dht_names" "30m" (map ({
          role,
          dna,
          part,
        }:
          recorded "holochain:dht_names" (target "lab-1"
            // {
              conductor = "Workshop";
              app_id = "mystery";
              inherit role dna;
              app_name = "Unnamed app";
              part_name = part;
              network_label = "Unnamed app: ${part}";
            })
          1) [
          {
            role = "rFiles";
            dna = "dnaF";
            part = "Files";
          }
          {
            role = "requests_and_offers";
            dna = "dnaR";
            part = "Requests and offers";
          }
        ]))
        (expect "max by (network_label) (holochain:dht_state:named)" "30m" [
          (sample {network_label = "Unnamed app: Files";} 3)
          (sample {network_label = "Unnamed app: Requests and offers";} 3)
        ])
        (expect "holochain:node_problem" "30m" [
          (recorded "holochain:node_problem" {
              instance = "lab-1:9100";
              node = "lab-1";
              problem = "Some app parts have no name yet";
            }
            2)
        ])
      ];
    }

    {
      name = "node states: a conductor down, a node unreachable, a node without Holochain";
      input_series =
        [(up "lab-1" 1) (up "lab-2" 0) (up "lab-3" 1)]
        ++ conductor {node = "lab-1";}
        ++ conductor {
          node = "lab-1";
          name = "Moss";
          isUp = 0;
        };
      promql_expr_test = [
        (expect "max by (conductor) (holochain:conductor_state)" "30m" [
          (sample {conductor = "Workshop";} 3)
          (sample {conductor = "Moss";} 1)
        ])
        (expect nodeStates "30m" [
          (sample {node = "lab-1";} 1)
          (sample {node = "lab-2";} 0)
          (sample {node = "lab-3";} 4)
        ])
        (expect "holochain:node_problem" "30m" [
          (recorded "holochain:node_problem" {
              instance = "lab-1:9100";
              node = "lab-1";
              conductor = "Moss";
              problem = "Holochain (Moss) is not answering";
            }
            0)
        ])
      ];
    }

    {
      name = "conductors under the default name: Holochain, said once";
      input_series =
        [(up "lab-1" 1) (up "lab-2" 1)]
        ++ conductor {
          node = "lab-1";
          name = "Holochain";
          stamp = "0+60x10 600x50";
        }
        ++ conductor {
          node = "lab-2";
          name = "Holochain";
          isUp = 0;
        };
      promql_expr_test = [
        (expect "holochain:node_problem" "30m" [
          (recorded "holochain:node_problem" {
              instance = "lab-1:9100";
              node = "lab-1";
              conductor = "Holochain";
              problem = "Holochain readings are over 90 s old";
            }
            0)
          (recorded "holochain:node_problem" {
              instance = "lab-2:9100";
              node = "lab-2";
              conductor = "Holochain";
              problem = "Holochain is not answering";
            }
            0)
        ])
      ];
    }

    {
      name = "a machine in trouble: problems in words";
      input_series = let
        at = target "lab-1";
      in
        [(up "lab-1" 1)]
        # One failed unit with no name, one named in the default overviewUnits
        # and one named by a regex key of it; each problem names its unit.
        ++ lib.concatMap (unit: [
          (unitState at unit "failed" 1)
          (unitState at unit "active" 0)
        ]) ["x.service" "holochain-conductor.service" "docker-wind-tunnel-runner.service"]
        ++ disk at "sda1" "ext4" "/" 5
        ++ [
          (series "node_memory_MemAvailable_bytes" at (hold 5))
          (series "node_memory_MemTotal_bytes" at (hold 100))
          (temperature at 90)
          (series "node_textfile_scrape_error" at (hold 1))
        ];
      promql_expr_test = [
        (expect "count by (node, problem) (holochain:node_problem)" "30m" (map (problem:
          sample {
            node = "lab-1";
            inherit problem;
          }
          1) [
          "x.service has failed"
          "Holochain conductor has failed"
          "Wind Tunnel runner has failed"
          "A disk is over 90% full"
          "Memory is over 90% used"
          "Running hot (over 85 °C)"
          "A metrics file could not be read (see the node_exporter log)"
        ]))
        (expect nodeStates "30m" [(sample {node = "lab-1";} 4)])
      ];
    }

    {
      # Just under every threshold, and a full tmpfs, which is not a disk
      # anyone fills: nothing to act on. Without this case a rule that fired
      # on any machine would still pass the one above.
      name = "a healthy machine: no problem";
      input_series = let
        at = target "lab-1";
      in
        [
          (up "lab-1" 1)
          (unitState at "x.service" "failed" 0)
          (unitState at "x.service" "active" 1)
        ]
        ++ disk at "sda1" "ext4" "/" 11
        ++ disk at "tmpfs" "tmpfs" "/run" 0
        ++ [
          (series "node_memory_MemAvailable_bytes" at (hold 11))
          (series "node_memory_MemTotal_bytes" at (hold 100))
          (temperature at 84)
          (series "node_textfile_scrape_error" at (hold 0))
        ];
      promql_expr_test = [
        (expect "holochain:node_problem" "30m" [])
      ];
    }
  ];

  tests = pkgs.writeText "holochain-rules-tests.json" (builtins.toJSON {
    rule_files = ["${rules}"];
    evaluation_interval = "1m";
    tests = map (case: {interval = "1m";} // case) cases;
  });
in
  pkgs.runCommand "holochain-rules" {
    nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli];
  } ''
    cat ${rules}

    # The homelab case's input: the two fixture conductors' textfiles, both
    # on one instance, with readings that keep pace with the test clock.
    cat ${textfiles}/workshop.prom ${textfiles}/moss.prom | grep -v '^#' \
      | sed -E 's/^([a-z_]+)\{/\1{instance="homelab:9100",job="${job}",node="homelab",site="Soushi home",/' \
      | jq -R '. as $l | capture("^(?<s>.*) (?<v>[^ ]+)$")
          | {series: .s,
             values: (if (.s | startswith("holochain_conductor_metrics_scrape_timestamp_seconds{"))
                      then "${fresh}" else "\(.v)+0x60" end)}' \
      | jq -s . > homelab.json
    echo "homelab input: $(jq length homelab.json) series"
    test "$(jq '[.[] | select(.series | startswith("up{"))] | length' homelab.json)" = 0
    jq --slurpfile homelab homelab.json '
      .tests |= map(if .name | startswith("the homelab")
        then .input_series = $homelab[0] + [{series: "up{instance=\"homelab:9100\", job=\"${job}\", node=\"homelab\", site=\"Soushi home\"}", values: "1+0x60"}]
        else . end)' ${tests} > tests.json

    promtool test rules tests.json

    # Each expectation broken on its own must fail its test.
    broken=0
    for i in $(seq 0 $(($(jq '.tests | length' tests.json) - 1))); do
      for j in $(seq 0 $(($(jq ".tests[$i].promql_expr_test | length" tests.json) - 1))); do
        jq --argjson i "$i" --argjson j "$j" '
          .tests = [.tests[$i] | .promql_expr_test = [.promql_expr_test[$j]
            | if (.exp_samples | length) > 0
              then .exp_samples[0].value += 1
              else .exp_samples = [{labels: "{}", value: 1}]
              end]]' tests.json > broken.json
        if promtool test rules broken.json > broken.log 2>&1; then
          echo "still passes with a wrong expectation:" >&2
          jq -c '.tests[0] | {name, test: .promql_expr_test[0]}' broken.json >&2
          exit 1
        fi
        if ! grep -q 'got:' broken.log; then
          echo "failed for another reason than the expectation:" >&2
          cat broken.log >&2
          exit 1
        fi
        broken=$((broken + 1))
      done
    done
    echo "$broken expectations, each seen to fail when wrong"
    touch $out
  ''
