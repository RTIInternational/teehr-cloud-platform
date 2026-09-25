resource "aws_efs_file_system" "datadir" {
  tags = {
    Name = "hub-datadir"
  }

  # PARKED 2026-09 -- do not enable until the storage cleanup lands.
  #
  # A cleanup pass was requested after this was written, and it invalidates
  # the measurements below. Both inputs to the decision move: deleting cold
  # data changes the age mix, and removing or consolidating small files
  # changes the 128 KiB rounding penalty, which is currently the single
  # biggest factor in what tiering would actually cost. Re-measure before
  # uncommenting -- the /data inventory walk and the sizing script behind
  # these numbers are described in RTIInternational/teehr-hub#422.
  #
  # Kept here rather than deleted so the analysis is not lost. Uncomment
  # throughput_mode and both lifecycle_policy blocks together: Archive is
  # rejected on a Bursting file system, and Elastic on its own would just add
  # ~$2.15/mo of I/O billing for no benefit.
  #
  # ---------------------------------------------------------------------
  #
  # Tier cold data off Standard.
  #
  # This file system held ~938 GiB with no lifecycle policy at all, so every
  # byte sat in Standard at ~$0.30/GiB-mo (~$281/mo). A walk of ~30% of the
  # tree in 2026-09 found the data is overwhelmingly cold: 98.3% of the bytes
  # had an mtime older than 90 days and 60.7% older than a year, while only
  # 1.0% had been touched in the last 30 days. It is user and project working
  # data (playground/, data_processing/backfill-nwm/, benchmarks/), not Spark
  # scratch -- temp-spark/ is under a gigabyte.
  #
  # Measured I/O backs this up: the file system averages 5-9 KB/s with burst
  # credits pegged at maximum, so essentially nothing is being read and the
  # per-GB IA/Archive retrieval charges should be negligible.
  #
  # Expected effect: ~$281/mo -> ~$21-40/mo. That is well short of a naive
  # storage-rate calculation because EFS meters IA and Archive with a 128 KiB
  # minimum billable size per file, and this file system is dominated by tiny
  # files: 1.07M of them are under 1 KiB. Measured against the real inventory,
  # 279 GiB of cold data bills as 614 GiB once rounded -- a 2.2x inflation.
  # Consolidating those small files (much of it fragmented Spark parquet
  # output) would now save more than any further storage-class tuning.
  #
  # transition_to_primary_storage_class is deliberately NOT set. With
  # AFTER_1_ACCESS a single full-tree scan (a stray du or find) would drag
  # everything back to Standard and bill the retrieval. Leaving it unset keeps
  # files in their tier when read, which is what we want for cold archives.
  #
  # Nothing about the mount changes: same paths, permissions and POSIX
  # semantics, and metadata always stays in Standard so listings stay fast.
  # Transitions happen gradually and the policy is reversible.
  #
  # Elastic throughput, not the previous Bursting, for two reasons:
  #
  #  1. Archive requires it. PutLifecycleConfiguration rejects
  #     TransitionToArchive outright on a Bursting file system.
  #  2. Bursting baseline throughput scales with the data held in STANDARD
  #     (~50 KB/s per GiB). Tiering ~920 GiB away would leave ~10 GiB in
  #     Standard and collapse the baseline to roughly 0.5 MB/s, making /data
  #     painful to use. Elastic decouples throughput from storage entirely.
  #
  # Elastic bills per byte moved ($0.03/GB read, $0.06/GB write) instead of a
  # size-derived baseline. At measured volumes -- 22 GB read and 24.9 GB
  # written over 30 days -- that is ~$2.15/mo. It also drops the IA storage
  # rate from $0.025 to $0.016/GiB-mo. Note AWS enforces a cooldown between
  # throughput mode changes, so this cannot be flipped back and forth freely.
  # throughput_mode = "elastic"

  # lifecycle_policy {
  #   transition_to_ia = "AFTER_30_DAYS"
  # }

  # lifecycle_policy {
  #   transition_to_archive = "AFTER_90_DAYS"
  # }

  lifecycle {
    # Additional safeguard against deleting the EFS
    # as this causes irreversible data loss!
    prevent_destroy = true
  }
}

resource "aws_efs_mount_target" "datadir" {
  file_system_id  = aws_efs_file_system.datadir.id
  subnet_id       = module.vpc.private_subnets[0]
  security_groups = [aws_security_group.efs-sg.id]
}

resource "aws_security_group" "efs-sg" {
  name_prefix = "${local.cluster_name}-efs-sg"
  description = "Allow EFS access"
  vpc_id      = module.vpc.vpc_id

  # egress {
  #   from_port        = 0
  #   to_port          = 0
  #   protocol         = "-1"
  #   cidr_blocks      = ["0.0.0.0/0"]
  #   ipv6_cidr_blocks = ["::/0"]
  # }

  ingress {
    description = "EFS mount target"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.cluster_name}-efs-sg" })
}
