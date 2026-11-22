



4. EBS gp3 via the CSI driver for low-latency block storage. EFS was rejected because NFS semantics and latency don't suit InnoDB. AZ-locality of EBS is mitigated by cross-AZ MySQL replication." That shows you made the choice deliberately.
5. Why create your own class rather than use gp2: the existing gp2 class uses the older disk type, deletes the disk when the PVC is deleted (risky for a database), can't expand, and isn't the default. Your gp3 class fixes all four.
6. kubectl create secret generic mysql-auth -n <namespace> \
   --from-literal=root-password='<choose>' \
   --from-literal=replication-password='<choose>'
7. for mysql replication we use GTID for Easier replication setup: Without GTID we must give a binlog file and position (MASTER_LOG_FILE, MASTER_LOG_POS). With GTID we just use SOURCE_AUTO_POSITION=1, and the replica works out what it's missing. Simple failover: When you promote a replica, the others can repoint to it without calculating positions. Tools like Orchestrator, MySQL Router and InnoDB Cluster rely on this.
   Consistency: Each transaction is applied only once on a replica. Already-executed GTIDs are skipped.
   Easy to check: Compare gtid_executed across servers to see if they're in sync.
8. 