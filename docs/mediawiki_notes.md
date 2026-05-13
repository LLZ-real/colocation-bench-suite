# DCPerf MediaWiki workload recovery notes

## Current status

Recovered:

- HHVM 3.30.12 is restored from /home/lilinzhen/colocate_lab/persist/hhvm-3.30.
- HHVM can run ordinary PHP.
- `perf.php --help` works.
- wrk exists under benchmarks/oss_performance_mediawiki/wrk/wrk.
- Nginx is installed.
- MariaDB is installed and can start.
- MediaWiki target files exist, including mediawiki-1.28.0.tar.gz and mw_bench.sql.gz.

Current failure:

- Full `oss_performance_mediawiki_mlp` still fails.
- HHVM segfaults when running `perf.php` with the MediaWiki MLP benchmark parameters.
- `no_jit` does not fix the crash.
- `--no-memcached` does not fix the crash.

Important observation:

- The current MariaDB instance does not show the `mw_bench` database.
- This suggests that the MediaWiki target install/init stage is incomplete or has not successfully run in the current container/volume state.

## Do not run during formal TaoBench experiments

The MediaWiki container uses online-server-like CPU placement. Running MediaWiki during TaoBench + SPEC experiments can pollute results.

During formal experiments, only perform static checks or documentation work.

## Next steps after current SPEC experiment finishes

1. Confirm memcached path:
   /usr/local/memcached/bin/memcached

2. Check composer/vendor under:
   /workspace/DCPerf/oss-performance/vendor

3. Check root database password:
   mysql -uroot -ppassword -e "SHOW DATABASES;"

4. Try a lightweight non-MediaWiki target:
   toys-hello-world

5. If toys works, run a MediaWiki setup-only test.

6. Only after setup succeeds and `mw_bench` exists, retry a 1-minute MediaWiki smoke test.
