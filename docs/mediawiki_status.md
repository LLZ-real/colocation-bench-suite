# MediaWiki workload status

## Current status

The DCPerf MediaWiki workload is not yet runnable in the current container.

Recovered components:

- HHVM 3.30.12 restored from persistent directory.
- HHVM can run ordinary PHP.
- HHVM legacy mysql extension works.
- MariaDB, Nginx, wrk, and memcached are installed.
- mw_bench database can be created and imported.
- HHVM can connect to mw_bench and query MediaWiki tables.

Remaining failure:

- `perf.php --mediawiki-mlp` segfaults.
- `perf.php --mediawiki` also segfaults.
- `perf.php --toys-hello-world` also segfaults.

Interpretation:

Because `toys-hello-world` also segfaults, the current failure is not specific to the MediaWiki database or MediaWiki target. The issue is likely in the generic oss-performance runner path, especially around HHVM daemon/server-mode startup under the current container environment.

Decision:

MediaWiki is paused and moved to a separate recovery track. The main experiment continues with TaoBench + iBench / SPEC CPU.
