# Turns the per-connection byte and message counts of one `dump-network-stats`
# reply into totals that only ever go up, so Prometheus can take rate() of them.
#
# The reply carries counts per connection the conductor holds right now. Summed
# as they are, a peer that disconnects takes its counts out of the sum and the
# "counter" drops, which rate() reads as a reset and draws as a burst of traffic
# that never happened. So the timer keeps a small state file between runs: the
# counts it last saw per connection, and the running totals. Each run adds to
# the totals what every connection sent or received since the previous run.
#
# Input: the reply (or {} when the conductor did not answer).
# $prev: the previous state, {} on the first run or after the file was lost.
# Output: the new state, {connections: {key: counts}, totals: counts}.
#
# A connection is keyed by pub_key and opened_at_s, so a peer that reconnects is
# a new connection counted from zero. A count lower than last time can only mean
# the same key was reused for a fresh connection, and is also counted from zero.
# What a connection moved between the last run and its closing is never seen,
# so the totals undercount by at most one interval of a closing connection.
# Losing the state file starts the totals from zero again, which Prometheus
# handles as the counter reset it is.

def fields: ["send_bytes", "recv_bytes", "send_message_count", "recv_message_count"];

($prev.connections // {}) as $was
| ($prev.totals // {}) as $total
| [(.transport_stats.connections // [])[]
    | {key: "\(.pub_key)@\(.opened_at_s)",
       value: (. as $c | reduce fields[] as $f ({}; .[$f] = ($c[$f] // 0)))}]
| from_entries as $now
| {
    connections: $now,
    totals: (reduce fields[] as $f ({};
      .[$f] = (($total[$f] // 0)
        + ([$now | to_entries[]
            | .value[$f] as $n
            | (($was[.key] // {})[$f] // 0) as $w
            | if $n >= $w then $n - $w else $n end]
           | add // 0))))
  }
