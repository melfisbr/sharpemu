SharpEmu V74.0.67.2.9
DLSS Source Identity De-dup SAFE

RUNTIME ROOT CAUSE
==================
V74.0.67.2.7 is active, but its scene-source ranking compares individual
pre-composite candidates rather than unique scene source identities.

The runtime repeatedly showed:

  candidates=5
  winner = same Source.Address
  runner = same Source.Address
  confidence_advantage=0
  sum_advantage=0
  reason=ambiguous_precomposite_source

At the same time the same source already had high, stable depth and motion
confidence, including R16G16Sfloat motion vectors.

Therefore the ambiguity is artificial: multiple temporal bindings for one
GuestImageResource are being treated as competing scene sources.

V74.0.67.2.9
=============
For largest-area candidates:

1. gather all raw candidates;
2. GroupBy(Source.Address);
3. choose one representative for each source identity:
   newest Source.ContentGeneration, then newest Binding.Serial;
4. calculate depth/motion confidence once per distinct source;
5. rank only distinct sources;
6. enforce that winner and runner-up can never share Source.Address.

If five raw candidates all represent one source, expected telemetry is:

  raw_candidates=5
  distinct_sources=1
  state=selected

No Demon's Souls address is hardcoded.

Preserved:
- V74.0.67.2.8 strict extension negotiation;
- V74.0.67.2.7 temporal scoring;
- V74.0.67.2.5 depth;
- V74.0.67.2.6 motion;
- V74.0.73 hot path;
- invalid DLSS downscale guard;
- existing native Vulkan/NGX provider.

The native provider is NOT rebuilt by this package because the runtime blocker
is before NGX dispatch, entirely inside managed source selection.

DLSS is proven active only when:
  selected=dlss
  state=active
  dlss_dispatches>0
