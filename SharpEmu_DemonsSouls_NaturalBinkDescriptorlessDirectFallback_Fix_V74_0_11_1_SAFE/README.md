# V74.0.11.1 — Native-lane semantic prerequisite repair

V74.0.11 was blocked before applying the Bink correction because it required
an exact NativeWorker SHA:

reference: `F4AF1A786A5F949F420050BA763762918D1AFAD98270684A26EBF5E6D1B82E38`
current checkout: `8E0FE4E3C23860592E29A9A5B2EA5D6AE974D221098D2ABBB31474087124CFC3`

That is too strict after V74.0.10 has already been runtime-proven.

V74.0.11.1 does not overwrite `DirectExecutionBackend.NativeWorker.cs`.
Instead it verifies the actual checkout semantically. It requires all of:

- `SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE`
- `RendererResourceNativeWorkerMaxConcurrent`
- `_rendererResourceNativeWorkerRunLimiter`
- `UsesRendererResourceNativeWorkerLane`
- renderer/resource concurrency environment variable
- HighGraphics/Core.Res/Nexus lane names
- V74.0.3.4 no-managed-inline marker
- V73.20.4.1 dedicated generic executor marker
- raw `NativeGuestExecutor` path

Only after that contract passes does it install the **same audited V74.0.11
presenter payload**.

Presenter baseline:
`0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66`

Presenter V74.0.11/11.1 payload:
`B837FD073B69E1656F4CA3475259CF911DFA011F161E45450F8D19822A6C4F41`

The runtime correction remains exactly the same:
natural Bink descriptorless direct fallback + render-tick decoder pump +
immediate release when a real guest Y/UV pair appears.
