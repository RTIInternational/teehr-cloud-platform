resource "aws_efs_file_system" "datadir" {
  tags = {
    Name = "hub-datadir"
  }

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
  # Expected effect: ~$281/mo -> ~$10/mo. IA alone would reach ~$15/mo, so if
  # the Archive transition ever has to be dropped, most of the saving remains.
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
  # NOTE: throughput_mode is "bursting", where baseline throughput scales with
  # the amount of data in STANDARD (~50 KB/s per GiB). Moving the bulk to IA
  # lowers that baseline proportionally. That is fine at current usage (5-9
  # KB/s against a ~50 MB/s baseline), but if /data ever becomes a hot path,
  # switch to Elastic throughput rather than reverting this policy.
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_archive = "AFTER_90_DAYS"
  }

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
