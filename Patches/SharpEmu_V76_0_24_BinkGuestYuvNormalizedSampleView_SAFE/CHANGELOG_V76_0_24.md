# V76.0.24 Bink Guest YUV Normalized Sample View

- Guest remains the only Bink2 decoder owner.
- Separates storage numeric identity from sample numeric identity.
- Final Bink Y plane: storage R8Uint, sampled alias R8Unorm.
- Final Bink UV plane: storage R8G8Uint, sampled alias R8G8Unorm.
- No CPU upload/copy and no host decoder.
- Adds A/B environment switch and telemetry.
