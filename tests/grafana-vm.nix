# Called from nix/checks.nix with the per-system arguments of
# nix/shared.nix.
# One node wearing both roles: an edgenode exporting its conductor's
# own stats, and the monitor scraping and drawing them. That is the
# whole observability path in a single VM, so a break anywhere in it
# fails here rather than at the workshop.
{
  deadTarget,
  dinoAdventureHapp,
  edgenodeNode,
  fixtureTextfiles,
  grafanaTestPassword,
  pkgs,
  roomToWork,
  self,
  ...
}:
pkgs.testers.nixosTest {
  name = "holochain-grafana-smoke";
  nodes.machine = {
    imports = [
      edgenodeNode
      roomToWork
      self.nixosModules.holochain-grafana
    ];
    environment.systemPackages = [pkgs.jq];
    services.holochain-edgenode = {
      enable = true;
      metricsExporter.enable = true;
      conductorMetrics.enable = true;
      # An app gives the conductor DHTs, without which the per-DHT
      # panels would have no series to query.
      happs.dino-adventure = {
        src = dinoAdventureHapp;
        networkSeed = "ci-test-seed";
      };
    };
    # Root-owned 0400, as the option reference tells operators to
    # create it: systemd reads it, the grafana user never does.
    systemd.tmpfiles.rules = [
      "d /var/lib/secrets 0700 root root - -"
      "f /var/lib/secrets/grafana-admin-password 0400 root root - ${grafanaTestPassword}"
    ];
    services.holochain-grafana = {
      enable = true;
      # The file path, not the plaintext option: this is what the
      # fleet uses, and the credential hand-off is what can break.
      adminPasswordFile = "/var/lib/secrets/grafana-admin-password";
      # The second target has nothing listening, so the dashboard
      # has a node that is down to show, next to one that is up.
      # Named, as a homelab names its nodes: both are on loopback,
      # where a list would name both after this machine.
      scrapeTargets = {
        machine = {
          address = "127.0.0.1:9100";
          site = "CI";
        };
        unplugged.address = deadTarget;
      };
      openFirewall = true;
      # Added to the default list rather than replacing it, both at
      # option-default priority, so the test sees the default units
      # and proves the option reaches the provisioned JSON.
      overviewUnits = pkgs.lib.mkOptionDefault ["systemd-journald.service" "always-fails.service"];
      # The Workshop fixture's app, so the room screen's write chart
      # has lines once the fixtures are written.
      room = {
        app = "requests-and-offers";
        part = "requests_and_offers";
        label = "Requests & Offers";
      };
    };
    # A unit in the failed state, for the Overview to show as one.
    systemd.services.always-fails = {
      description = "A unit that always fails, for vmTestGrafana";
      wantedBy = ["multi-user.target"];
      script = "exit 1";
    };
    # One that fails and is not watched: the problem list still
    # names it, since no panel that filters on the watched units
    # would.
    systemd.services.fails-unwatched = {
      description = "A unit that always fails and is not in overviewUnits, for vmTestGrafana";
      wantedBy = ["multi-user.target"];
      script = "exit 1";
    };
  };
  testScript = {nodes, ...}: let
    # Two more conductors on this node, Workshop and Moss, as the
    # exporter writes them, in textfiles of their own beside the
    # live conductor's. Their readings are dated an hour ahead, so
    # they stay fresh while the test runs.
    textfileDir = nodes.machine.services.holochain-edgenode.metricsExporter.textfileDirectory;
    writeFixtures = pkgs.writeShellScript "write-fixture-textfiles" ''
      set -eu
      stamp=$(($(date +%s) + 3600))
      for name in workshop moss; do
        sed -E "s/^(holochain_conductor_metrics_scrape_timestamp_seconds[{][^}]*[}]) .*/\1 $stamp/" \
          ${fixtureTextfiles}/$name.prom > ${textfileDir}/.fixture-$name.tmp
        mv ${textfileDir}/.fixture-$name.tmp ${textfileDir}/fixture-$name.prom
      done
    '';
    # The Holochain this node's conductor runs, from its package.
    holochainVersion = pkgs.lib.getVersion nodes.machine.services.holochain-edgenode.package;
    # The record names of the rule file this node runs.
    records =
      map (rule: rule.record)
      (builtins.head
        (import ../observability/rules.nix {
          interval = nodes.machine.services.holochain-grafana.scrapeInterval;
          inherit (nodes.machine.services.holochain-grafana) states;
        }).groups).rules;
  in ''
    import base64
    import json
    import re
    import shlex

    machine.wait_for_unit("grafana.service")
    machine.wait_for_unit("prometheus.service")
    machine.wait_for_open_port(3000)
    machine.wait_for_open_port(9090)
    machine.succeed("curl -sf http://localhost:3000/api/health")

    # NixOS 26.05 dropped Grafana's default secret key; the module
    # generates one at first boot, outside the store, and keeps it.
    key_stat = machine.succeed("stat -c '%a %U' /var/lib/grafana/secret_key").strip()
    assert key_stat == "400 grafana", key_stat
    key_before = machine.succeed("sha256sum /var/lib/grafana/secret_key")
    machine.succeed("systemctl restart grafana-secret-key.service grafana.service")
    machine.wait_for_open_port(3000)
    assert machine.succeed("sha256sum /var/lib/grafana/secret_key") == key_before, (
        "the secret key was regenerated on restart"
    )

    # ---- criterion 4: the conductor's own series ----
    machine.wait_for_unit("holochain-conductor.service")
    machine.wait_for_unit("holochain-conductor-metrics.timer")
    machine.wait_for_unit("holochain-happ-installer.service")

    # The timer fires on its interval; the first file may not exist
    # yet when the conductor has only just come up.
    machine.wait_until_succeeds(
        "curl -s localhost:9100/metrics | grep '^holochain_'", timeout=180
    )
    holochain_metrics = machine.succeed(
        "curl -s localhost:9100/metrics | grep '^holochain_'"
    )
    machine.log("holochain series on /metrics:\n" + holochain_metrics)
    assert 'holochain_conductor_up{conductor="Holochain"} 1' in holochain_metrics, (
        "the conductor answered dump-network-stats nowhere:\n" + holochain_metrics
    )

    # ---- criterion 3: the live target is up, the dead one down ----
    machine.wait_until_succeeds(
        "curl -s localhost:9090/api/v1/targets"
        " | jq -e '[.data.activeTargets[] | {(.labels.instance): .health}] | add"
        " | .[\"127.0.0.1:9100\"] == \"up\" and .[\"${deadTarget}\"] == \"down\"'",
        timeout=120,
    )
    targets = machine.succeed(
        "curl -s localhost:9090/api/v1/targets"
        " | jq -c '.data.activeTargets[] | {scrapeUrl, health, lastError}'"
    )
    machine.log("prometheus targets:\n" + targets)

    # Prometheus has to have kept the conductor series, not merely
    # scraped it once: this is what the dashboard actually queries.
    # The target goes "up" on its first scrape, which can land before
    # the metrics timer has written its first textfile, so this waits
    # for a scrape that carries the series rather than asserting once.
    machine.wait_until_succeeds(
        "curl -s --get localhost:9090/api/v1/query"
        " --data-urlencode 'query=holochain_conductor_up'"
        " | jq -e '.data.result | length > 0'",
        timeout=180,
    )
    series = machine.succeed(
        "curl -s --get localhost:9090/api/v1/query"
        " --data-urlencode 'query=holochain_conductor_up'"
        " | jq -c '.data.result'"
    )
    machine.log("holochain_conductor_up in prometheus: " + series)
    assert '"__name__":"holochain_conductor_up"' in series, series

    # ---- criterion 5: the five dashboards, "What is this machine running?" at home ----
    def grafana(path):
        return json.loads(machine.succeed(
            "curl -sf -u admin:${grafanaTestPassword}"
            f" 'http://localhost:3000{path}'"
        ))


    # Exactly the five, and nothing else wearing their tag.
    def the_five(path):
        uids = sorted(d["uid"] for d in grafana(path))
        machine.log(f"{path}: " + json.dumps(uids))
        return uids == ["holochain-fleet", "holochain-home", "holochain-network", "holochain-node", "holochain-now"]


    tagged = sorted(d["uid"] for d in grafana("/api/search?tag=holochain"))
    assert the_five("/api/search?tag=holochain"), tagged
    # The same test on an answer Grafana gives with one short must fail.
    assert not the_five("/api/search?tag=holochain&limit=4")

    # Grafana's home page is "What is this machine running?".
    # Grafana answers with the dashboard itself, or with a redirect
    # to it when the home page is a saved preference.
    def is_home(answer):
        uid = answer.get("dashboard", {}).get("uid")
        machine.log(f"dashboard: uid {uid!r}, redirect {answer.get('redirectUri')!r}")
        return uid == "holochain-home" or "/d/holochain-home" in answer.get("redirectUri", "")


    home = grafana("/api/dashboards/home")
    assert is_home(home), "the home page is not What is this machine running?: " + json.dumps(home)[:500]
    # Another dashboard, in the same shape of answer, must not pass.
    assert not is_home(grafana("/api/dashboards/uid/holochain-now"))
    # It opens on this machine, the target on loopback, named machine.
    home_node = next(v for v in home["dashboard"]["templating"]["list"] if v["name"] == "node")["current"]
    assert home_node.get("value") == "machine", home_node

    # A provisioned dashboard that Grafana cannot bind to a data
    # source renders empty panels, which a search hit would not show.
    datasource = machine.succeed(
        "curl -s -u admin:${grafanaTestPassword}"
        " http://localhost:3000/api/datasources/uid/holochain-prometheus"
    )
    machine.log("grafana datasource: " + datasource)
    assert '"type":"prometheus"' in datasource, datasource

    # Prometheus must hold the series the pages are built on, not
    # merely accept the queries.
    def prom_file(expr, name):
        encoded = base64.b64encode(expr.encode()).decode()
        machine.succeed(f"echo {encoded} | base64 -d > /tmp/{name}")
        return f"/tmp/{name}"


    def prom_query(path):
        return json.loads(machine.succeed(
            f"curl -s --get localhost:9090/api/v1/query --data-urlencode query@{path}"
        ))


    def wait_non_empty(expr, name, timeout=180):
        path = prom_file(expr, name)
        machine.wait_until_succeeds(
            f"curl -s --get localhost:9090/api/v1/query --data-urlencode query@{path}"
            " | jq -e '.status == \"success\" and (.data.result | length > 0)'",
            timeout=timeout,
        )
        return prom_query(path)["data"]["result"]


    result = wait_non_empty(
        'node_systemd_unit_state{name="holochain-conductor.service",state="active"} == 1',
        "q-conductor-unit",
    )
    machine.log("conductor unit active: " + json.dumps(result))

    # The live conductor's own app: one DHT per role, each with a
    # name and none of them a key.
    dht_names = {
        r["metric"]["network_label"]
        for r in wait_non_empty('holochain_dht_info{app_id="dino-adventure"}', "q-dht-names")
    }
    machine.log("live DHTs: " + json.dumps(sorted(dht_names)))
    assert dht_names and all(n and "$" not in n and "uhC" not in n for n in dht_names), dht_names

    # The dashboards as Grafana serves them, after the module
    # rewrote them.
    served = {uid: grafana(f"/api/dashboards/uid/{uid}")["dashboard"] for uid in tagged}
    panels = {}
    for uid, dashboard in served.items():
        panels[uid] = []
        for panel in dashboard["panels"]:
            panels[uid].append(panel)
            panels[uid].extend(panel.get("panels", []))
        machine.log(f"{uid}: " + ", ".join(p["title"] for p in panels[uid]))
    variables = {
        uid: {v["name"]: v for v in dashboard["templating"]["list"]}
        for uid, dashboard in served.items()
    }

    # The room constants, rewritten from the room option.
    room = {n: variables["holochain-now"][n]["current"]["value"] for n in ["room_app", "room_part", "room_label"]}
    machine.log("room constants: " + json.dumps(room))
    assert room == {
        "room_app": "requests-and-offers",
        "room_part": "requests_and_offers",
        "room_label": "Requests & Offers",
    }, room

    # The node page's node variable, run the way Grafana runs
    # label_values(): both targets, by name, the dead one included.
    definition = variables["holochain-node"]["node"]["definition"]
    m = re.fullmatch(r"label_values\((.*),\s*(\w+)\)", definition)
    assert m, f"unexpected node variable definition: {definition}"
    selector_file = prom_file(m.group(1), "q-node-selector")
    nodes = json.loads(machine.succeed(
        f"curl -s --get localhost:9090/api/v1/label/{m.group(2)}/values"
        f" --data-urlencode match[]@{selector_file}"
    ))["data"]
    machine.log("node variable values: " + json.dumps(nodes))
    assert sorted(nodes) == ["machine", "unplugged"], nodes

    # What the states look like. A swapped colour or a lost word
    # would leave every query passing.
    def panel(uid, title):
        # A collapsed row can share its title with the panel in it.
        return next(p for p in panels[uid] if p["title"] == title and p["type"] != "row")


    def words(mappings):
        return {
            value: (option["text"], option["color"])
            for m in mappings if m["type"] == "value"
            for value, option in m["options"].items()
        }


    def override(p, field, prop):
        return next(
            q["value"]
            for o in p["fieldConfig"]["overrides"] if o["matcher"]["options"] == field
            for q in o["properties"] if q["id"] == prop
        )


    grey, amber = "#8e8e8e", "#EAB839"
    app_words = {
        "0": ("Not running", "red"), "1": ("No fresh readings", "orange"),
        "2": ("Lost contact", "red"), "3": ("No one else yet", grey),
        "4": ("Catching up", amber), "5": ("In step", "green"),
    }
    node_words = {
        "0": ("Unreachable", "red"), "1": ("Holochain not answering", "red"),
        "2": ("A service is down", "red"), "3": ("No fresh readings", "orange"),
        "4": ("Running", "green"), "5": ("No Holochain here", grey),
    }
    service_words = {
        "0": ("Failed", "red"), "1": ("Stopped", "red"), "2": ("Not answering", "red"),
        "3": ("No fresh readings", "orange"), "4": ("Starting", amber),
        "5": ("Stopping", amber), "6": ("Running", "green"),
    }
    for uid, title in [("holochain-now", "Is each app working on each node?"),
                       ("holochain-fleet", "Is each app in step on each node?")]:
        assert words(panel(uid, title)["fieldConfig"]["defaults"]["mappings"]) == app_words, (uid, title)
    assert words(override(panel("holochain-node", "Is each app part connected, complete and recent?"), "State", "mappings")) == app_words
    assert words(panel("holochain-network", "Status on each node")["fieldConfig"]["defaults"]["mappings"]) == app_words
    assert words(panel("holochain-now", "Which machines are on?")["fieldConfig"]["defaults"]["mappings"]) == node_words
    assert words(override(panel("holochain-fleet", "Which node needs attention?"), "Status", "mappings")) == node_words
    assert words(panel("holochain-node", "Conductors")["fieldConfig"]["defaults"]["mappings"]) == {
        "1": ("Not answering", "red"), "2": ("No fresh readings", "orange"), "3": ("Running", "green"),
    }
    assert words(panel("holochain-fleet", "Node status over time")["fieldConfig"]["defaults"]["mappings"]) == node_words
    # The three service tables read their states in the same words,
    # and the home page's conductors and apps read theirs as the node
    # page does.
    for uid, title in [("holochain-fleet", "Which services are not running?"),
                       ("holochain-node", "Is each service on this machine running?"),
                       ("holochain-home", "Is each service running, and in which version?")]:
        assert words(override(panel(uid, title), "State", "mappings")) == service_words, (uid, title)
    assert words(override(panel("holochain-home", "Is each app on this machine working?"), "State", "mappings")) == app_words
    assert words(override(panel("holochain-home", "Which Holochain conductors run here?"), "State", "mappings")) == {
        "1": ("Not answering", "red"), "2": ("No fresh readings", "orange"), "3": ("Running", "green"),
    }
    assert words(panel("holochain-home", "State")["fieldConfig"]["defaults"]["mappings"]) == node_words

    # ---- node names and the recording rules, over three conductors ----
    # Every target carries its node's name, and its site when it has one.
    target_labels = json.loads(machine.succeed(
        "curl -s localhost:9090/api/v1/targets"
        " | jq -c '[.data.activeTargets[] | {(.labels.instance): (.labels | {node, site})}] | add'"
    ))
    machine.log("target labels: " + json.dumps(target_labels))
    assert target_labels == {
        "127.0.0.1:9100": {"node": "machine", "site": "CI"},
        "${deadTarget}": {"node": "unplugged", "site": None},
    }, target_labels

    def wait_values(expr, name, want, key, timeout=180):
        # Waits until the query answers exactly `want`, {key label: value}.
        path = prom_file(expr, name)
        want_json = json.dumps(want)
        assert "'" not in want_json, want_json
        machine.wait_until_succeeds(
            f"curl -s --get localhost:9090/api/v1/query --data-urlencode query@{path}"
            f" | jq -e --argjson want '{want_json}'"
            f" '[.data.result[] | {{(.metric.{key} // \"\"): .value[1]}}] | add == $want'",
            timeout=timeout,
        )
        machine.log(f"{expr}: {json.dumps(want)}")

    machine.succeed("${writeFixtures}")

    # node_exporter serves every series of the three files, with no
    # scrape error: the two fixtures declare their families exactly as
    # the live conductor's exporter does.
    fixture_dhts = 4 + 7
    wait_values('count(holochain_dht_peers{conductor=~"Workshop|Moss"})', "q-fixture-dhts", {"": str(fixture_dhts)}, "none")
    wait_values("count(holochain_dht_peers)", "q-all-dhts", {"": str(fixture_dhts + len(dht_names))}, "none")
    wait_values("max(node_textfile_scrape_error)", "q-scrape-error", {"": "0"}, "none")

    # Every rule of the file is loaded, has been evaluated, and has
    # not failed: a join that turns many-to-many on real series
    # fails the whole rule, with the reason in lastError.
    # Prometheus leaves lastError out of the reply when it is empty.
    records = json.loads('${builtins.toJSON records}')

    def rule_states():
        groups = json.loads(machine.succeed("curl -s localhost:9090/api/v1/rules"))["data"]["groups"]
        return [
            (r["name"], r["health"], r.get("lastError", ""), r["lastEvaluation"])
            for g in groups for r in g["rules"]
        ]

    # Only an evaluation that started after the fixtures were
    # visible says anything about them.
    since = int(machine.succeed("date +%s").strip()) + 1
    try:
        machine.wait_until_succeeds(
            "curl -s localhost:9090/api/v1/rules"
            f" | jq -e --argjson since {since} '[.data.groups[].rules[]"
            " | select(.health != \"ok\" or (.lastError // \"\") != \"\""
            " or (.lastEvaluation | sub(\"[.][0-9]+Z$\"; \"Z\") | fromdate) < $since)]"
            " | length == 0'",
            timeout=180,
        )
    finally:
        machine.log("rules: " + json.dumps(rule_states()))
    loaded = rule_states()
    assert sorted(r[0] for r in loaded) == sorted(records), (sorted(r[0] for r in loaded), records)
    for name, health, error, _ in loaded:
        assert health == "ok" and error == "", (name, health, error)

    # Every conductor answers, but always-fails.service, which
    # overviewUnits adds to the watched services, has failed: the
    # node reads A service is down, and the dead target reads
    # Unreachable, each by its name.
    wait_values("holochain:node_state", "q-node-state", {"machine": "2", "unplugged": "0"}, "node")
    wait_values('max by (conductor) (holochain:conductor_state)', "q-conductor-state",
                {"Holochain": "3", "Workshop": "3", "Moss": "3"}, "conductor")

    # The services of the machine by name, and nothing else: the ones
    # its modules installed, as the machine lists them, the two
    # overviewUnits adds, by their unit names, and the two fixture
    # conductors that no unit on the machine claims, the Moss one as
    # "Holochain conductor (Moss)". The live conductor is claimed by
    # its unit.
    wait_values('max by (service) (holochain:service_state{node="machine"})', "q-services", {
        "Holochain conductor": "6", "App installer": "6", "Holochain readings (timer)": "6",
        "Metrics database": "6", "Dashboards": "6", "Machine readings": "6", "Nix": "6",
        "systemd-journald.service": "6", "always-fails.service": "0",
        "Holochain conductor (Moss)": "6", "Holochain conductor (Workshop)": "6",
    }, "service")

    # Every service the machine's own modules list carries the
    # version of the package that runs it, as a label Prometheus
    # keeps; the readings timer has none.
    wait_values('max by (service, version) (holochain_service_info{node="machine", version!=""})', "q-versions", {
        "Holochain conductor": "1", "App installer": "1", "Metrics database": "1", "Dashboards": "1",
        "Machine readings": "1", "Nix": "1",
    }, "service")
    wait_values('count(holochain_service_info{node="machine", name="holochain-conductor.service", holochain_version="${holochainVersion}", version="${holochainVersion}"})',
                "q-conductor-version", {"": "1"}, "none")

    # The Moss node's shape: the connected chat and the group in step,
    # the chat nobody else opened alone and grey, not red.
    wait_values('max by (network_label) (holochain:dht_state:named{conductor="Moss"})', "q-moss-states", {
        "Sensorica: Members and tools": "5", "Sensorica: Foyer": "5", "Sensorica: Shared assets": "5",
        "General chat: Messages": "5", "General chat: Files": "5",
        "Vines 1: Messages": "3", "Vines 1: Files": "3",
    }, "network_label")
    # The live app is alone on its network: No one else yet.
    wait_values('max by (network_label) (holochain:dht_state:named{conductor="Holochain"})', "q-live-states",
                {n: "3" for n in dht_names}, "network_label")

    # In words: the two units that always fail, each by its name,
    # the watched one and the one no panel watches, and nothing else:
    # no disk, memory or heat problem on a healthy VM, and nothing
    # that would mean the readings or the names are broken.
    expected_problems = {"always-fails.service has failed", "fails-unwatched.service has failed"}
    machine.wait_until_succeeds(
        "curl -s --get localhost:9090/api/v1/query"
        " --data-urlencode 'query=count(holochain:node_problem{node=\"machine\", problem=~\".* has failed\"})'"
        " | jq -e '.data.result[0].value[1] == \"2\"'",
        timeout=120,
    )
    problems = {
        r["metric"]["problem"]
        for r in wait_non_empty('holochain:node_problem{node="machine"}', "q-problems")
    }
    machine.log("problems: " + json.dumps(sorted(problems)))
    assert problems == expected_problems, problems

    # ---- every panel of the four pages, through Grafana's own query API ----
    # With the three conductors present, each target goes to
    # /api/ds/query with its variables filled as Grafana fills them:
    # All for the multi-value ones, this node, the connected Moss
    # chat for the network page, the rewritten units and room
    # constants. Each must come back without an error and with at
    # least one frame holding a value. Three may be empty here and
    # must still not error: the two temperature panels, since QEMU
    # exposes no hwmon sensor, and "Same data everywhere", which
    # needs two nodes on one network (checks.dashboardQueries still
    # requires the rule it reads to be recorded). A query that
    # answers through an "or vector()" fallback answers here
    # whatever its left side reads; checks.dashboardQueries requires
    # every series its left side reads to be there.
    network = next(
        r["metric"]["dna"]
        for r in wait_non_empty(
            'holochain_dht_info{conductor="Moss", network_label="General chat: Messages"}', "q-network"
        )
    )
    machine.log("network page variable: " + network)


    def fill(expr):
        for name, value in [
            ("''${room_app}", room["room_app"]),
            ("''${room_part}", room["room_part"]),
            ("$network", network),
            ("$node", "machine"),
            ("$site", ".*"),
            ("$conductor", ".*"),
        ]:
            expr = expr.replace(name, value)
        assert "$" not in expr, f"unfilled variable in {expr}"
        return expr


    answered = (
        "(.results.A.error == null)"
        " and ([.results.A.frames[]? | (.data.values // []) | length > 0 and (.[-1] | length > 0)] | any)"
    )


    def ds_query(expr, instant, name):
        # The shell command that posts one query and prints the reply.
        body = {
            "from": "now-10m",
            "to": "now",
            "queries": [{
                "refId": "A",
                "datasource": {"type": "prometheus", "uid": "holochain-prometheus"},
                "expr": expr,
                "instant": instant,
                "range": not instant,
                "intervalMs": 15000,
                "maxDataPoints": 200,
            }],
        }
        encoded = base64.b64encode(json.dumps(body).encode()).decode()
        machine.succeed(f"echo {encoded} | base64 -d > /tmp/{name}.json")
        return (
            "curl -s -u admin:${grafanaTestPassword} -H 'Content-Type: application/json'"
            f" -X POST --data @/tmp/{name}.json http://localhost:3000/api/ds/query"
        )


    # No sensor, but the collector that would read one runs.
    wait_non_empty('node_scrape_collector_success{collector="hwmon"} == 1', "q-hwmon")
    may_be_empty = {"Same data everywhere"}
    answered_labels, empty_allowed = [], []
    for uid in tagged:
        for p in panels[uid]:
            for target in p.get("targets", []):
                expr = fill(target["expr"])
                name = f"ds-{uid}-{p['id']}-{target['refId']}"
                label = f"{uid} / {p['title']} [{target['refId']}]"
                command = ds_query(expr, target.get("instant", False), name)
                if "node_hwmon_temp_celsius" in expr or p["title"] in may_be_empty:
                    machine.succeed(f"{command} | jq -e '.results.A.error == null'")
                    machine.log(f"{label}: no error (may be empty here)")
                    empty_allowed.append(label)
                else:
                    try:
                        machine.wait_until_succeeds(f"{command} | jq -e '{answered}'", timeout=120)
                    except Exception:
                        machine.log(f"{label} did not answer: " + machine.succeed(command)[:2000])
                        raise
                    machine.log(f"{label}: answered")
                    answered_labels.append(label)
    # Counted apart, so the log says how many were required to
    # answer; the ones let off are exactly these three.
    machine.log(
        f"{len(answered_labels)} panel queries answered through /api/ds/query;"
        f" {len(empty_allowed)} only required not to error: " + json.dumps(empty_allowed)
    )
    assert sorted(empty_allowed) == [
        "holochain-fleet / Hottest sensor [A]",
        "holochain-network / Same data everywhere [A]",
        "holochain-node / Temperatures [A]",
    ], empty_allowed
    assert len(answered_labels) >= 70, len(answered_labels)

    # The same test on a query that cannot answer must fail, or the
    # sweep above proves nothing.
    machine.fail(f"{ds_query('holochain:no_such_rule', True, 'ds-broken')} | jq -e '{answered}'")

    # A negative matcher keeps every series whatever the label is
    # called, so a misspelled label would pass the sweep. Each label
    # a query matches negatively has to exist on its metric.
    negative = set()
    for uid in tagged:
        for p in panels[uid]:
            for target in p.get("targets", []):
                for metric, matchers in re.findall(r"([a-zA-Z_:][a-zA-Z0-9_:]*)\{([^}]*)\}", target["expr"]):
                    for label in re.findall(r"(\w+)\s*!(?:=|~)", matchers):
                        negative.add((metric, label))
    machine.log("negatively matched labels: " + json.dumps(sorted(negative)))
    assert negative, "no negative matcher found; the parser is broken"
    for n, (metric, label) in enumerate(sorted(negative)):
        wait_non_empty(f'count({metric}{{{label}!=""}})', f"q-negative-{n}")

    # node_exporter leaves mount units out unless told otherwise; the
    # modules tell it to, so a failed mount reaches the problem list.
    wait_non_empty('node_systemd_unit_state{name=~".+[.]mount"}', "q-mount-units")

    # The fixtures go, so what follows sees the live conductor alone.
    machine.succeed("rm ${textfileDir}/fixture-workshop.prom ${textfileDir}/fixture-moss.prom")
    wait_values("count(holochain_conductor_up)", "q-live-alone", {"": "1"}, "none")

    # ---- the conductor, failing in each of the ways the pages name ----
    def target_expr(uid, title, ref="A"):
        return fill(next(t["expr"] for t in panel(uid, title)["targets"] if t["refId"] == ref))


    conductors = target_expr("holochain-node", "Conductors")
    problems_expr = target_expr("holochain-fleet", "What needs a human?")

    def wait_conductor(value, timeout):
        wait_values(conductors, f"q-conductor-{value}", {"Holochain": str(value)}, "conductor", timeout=timeout)

    def wait_problem(sentence, timeout):
        path = prom_file(problems_expr, "q-problem")
        machine.wait_until_succeeds(
            f"curl -s --get localhost:9090/api/v1/query --data-urlencode query@{path}"
            f" | jq -e --arg p {shlex.quote(sentence)} 'any(.data.result[]; .metric.node == \"machine\" and .metric.problem == $p)'",
            timeout=timeout,
        )
        machine.log(f"problem named: {sentence}")

    # The rule reads Not answering before it reads stale, so the
    # stale case comes first, while the last file still says up.
    # No fresh readings: nothing writes any more, and the last file stays.
    machine.succeed("systemctl stop holochain-conductor-metrics.timer")
    wait_conductor(2, 360)
    wait_problem("Holochain readings are over 90 s old", 60)

    # Not answering: the timer writes again, and says so.
    machine.succeed("systemctl stop holochain-conductor.service")
    machine.succeed("systemctl start holochain-conductor-metrics.timer")
    wait_conductor(1, 180)
    wait_problem("Holochain is not answering", 60)

    # A textfile node_exporter cannot parse drops every series in
    # it: the problem list says so, and the room screen's readings
    # tile reads 1e9, which its mapping shows as "No readings" in red
    # (checks.dashboardWords holds the mapping). The timer
    # stops first, or its next run would replace the file, and so
    # does a run the timer already started, which would otherwise
    # finish after the write and overwrite the bad file.
    machine.succeed("systemctl stop holochain-conductor-metrics.timer holochain-conductor-metrics.service")
    machine.succeed(
        "echo 'not a metric line' > /var/lib/prometheus-node-exporter-text-files/holochain-conductor.prom"
    )
    wait_problem("A metrics file could not be read (see the node_exporter log)", 120)
    wait_values(target_expr("holochain-now", "Are these readings current?"), "q-no-readings", {"": "1000000000"}, "none", timeout=120)

    # A dashboard Grafana could not provision leaves an error in its
    # journal and nothing else.
    journal = machine.succeed("journalctl -u grafana --no-pager")
    offenders = [
        line
        for line in journal.splitlines()
        if "level=error" in line and "provisioning" in line
    ]
    assert not offenders, "grafana provisioning errors:\n" + "\n".join(offenders)
  '';
}
