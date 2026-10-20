# LINSTOR Storage Validation

Read-only validation for a converted Kubernetes worker. The role proves that
the root disk is approximately 250 GiB, exactly one unmounted 750 GiB data disk
matches the supplied serial, and `linstor_vg/linstor_thin` has at least 740 GiB
of thin data, 4 GiB of metadata, 64 GiB of free VG reserve, and the expected
auto-extension profile.

Set `linstor_storage_expected_serial` explicitly. All other thresholds have
safe defaults matching the permanent worker layout.
