# LINSTOR LVM

Creates an LVM thin pool only after matching one disk by exact serial and
size, proving it is not the root disk or mounted, and receiving an exact
per-host erase confirmation. It never wipes an unexpected signature.

