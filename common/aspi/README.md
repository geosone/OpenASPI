# Shared ASPI layer

This directory will hold ASPI-manager discovery through `SCSIMGR$`, SRB
definitions, manager chaining behavior required by clients, synchronous
submission, timeout handling, and host/target/LUN enumeration.

AHCIASPI and EUSBASPI provide the first free manager implementations used for
integration tests.  The layer must also remain compatible with historical
Adaptec managers.
