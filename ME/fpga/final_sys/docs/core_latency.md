# Decision Tree cycle timing

Open `core_latency_wavedrom.json` with the WaveDrom editor, or paste its JSON
content into https://wavedrom.com/editor.html.

The drawing shows a three-node path. The FSM takes two clocks per visited node:

```text
WAIT: BRAM read for the current node address
EVAL: compare feature and select child, or emit a leaf result
```

For `N` visited nodes, `result_valid` is asserted `2*N` 50-MHz clocks after
the clock edge that samples `start`.

| Path | Clocks | Core latency |
|---|---:|---:|
| Root is leaf | 2 | 40 ns |
| 3 nodes | 6 | 120 ns |
| 64 nodes | 128 | 2.56 us |
