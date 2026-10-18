# ASPIDSK.SYS

Planned general ASPI block driver for fixed disks, SSDs, USB sticks, card
readers, and direct-access removable devices using disk-style semantics.

The first implementation milestone is read-only enumeration and sector reads.
No loader skeleton is emitted yet because a block driver must return correct
unit count, BPB and media information during DOS initialization.
