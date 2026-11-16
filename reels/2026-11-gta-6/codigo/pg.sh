#!/bin/bash
pg_isready -q -p 5499 -h /var/lib/postgresql/teste-fazenda || { su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/teste-fazenda/data -o '-p 5499 -k /var/lib/postgresql/teste-fazenda' -l /var/lib/postgresql/teste-fazenda/log.txt start" >/dev/null 2>&1; sleep 3; }
