V61.23.5 SAFE

Corrects V61.23.4 rollback failure by using the actual structural insertion
point from V61.23.1:
  lock (_gate) {
      [V61.23.1 injected block]
      if (!_waiters.TryGetValue(address, out var list))
The package removes only the interval between the lock brace and the original
waiter-list statement.

No WAIT_REG_MEM is force-satisfied.
Real WRITE_DATA/DMA/RELEASE_MEM producer tracking is preserved.
Post-video diagnostic runs with high-frequency trace switches disabled.
