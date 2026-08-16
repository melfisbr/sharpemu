# V74.0.11.2 — System.Buffer compile repair

V74.0.11.1 passed its semantic/native-lane precheck and installed the intended
natural-Bink descriptorless fallback, but compilation found one C# error:

    VulkanVideoPresenter.cs(9765,13)
    CS0104: "Buffer" is ambiguous between
    "Silk.NET.Vulkan.Buffer" and "System.Buffer"

The new fallback used:

    Buffer.BlockCopy(...)

The accumulated presenter already uses the correct fully-qualified form
elsewhere:

    System.Buffer.BlockCopy(...)

V74.0.11.2 changes only that call. No Bink, Vulkan, scheduler, native-lane,
memory-budget, or Y/UV behavior is otherwise changed.

The V74.0.11.1 failed build restored the presenter, so the expected checkout
presenter baseline remains:

`0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66`

Corrected presenter payload:

`1F4D6BF5B71AC0B773052D0FFC9C267CF8C9A0CD3868A33E5368FE8F828088CA`

The NativeWorker is still never overwritten; the V74.0.10 native-lane
prerequisite remains semantic and accepts the runtime-proven accumulated
checkout.
