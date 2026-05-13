# Pre-flight Checklist

Send this to participants **one week before** the workshop.

---

## What to bring

- A laptop with one of:
  - (a) NixOS already installed, **or**
  - (b) A NixOS live USB ready to boot, **or**
  - (c) A spare machine you can wipe (we provide USB keys at the lab)
- Ethernet cable if you have one (workshop wifi is the enemy of P2P traffic)
- An SSH client you are comfortable with

## Optional but useful

- A second monitor (Kate + Konsole + Firefox side by side is the ideal layout)
- A basic understanding of what a systemd unit is

## No Nix experience required

You do not need to know Nix before the workshop. We will walk through the flake together before anyone touches a keyboard.

---

## Facilitator pre-flight (day before)

- [ ] Flash 5 USB keys with the workshop ISO
- [ ] Test ISO boots on at least one Holoport / NUC
- [ ] Verify `colmena apply` reaches all 5 nodes over the local network
- [ ] Confirm `windtunnel.happ` and `moss.happ` are in `happs/` and the hApp installer service starts cleanly
- [ ] Bring a dedicated router (tested) — do not rely on Sensorica lab wifi alone
- [ ] Print or share the participant handout
- [ ] Have Grafana dashboard URL ready on a shared screen
