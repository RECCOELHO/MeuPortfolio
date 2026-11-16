#!/bin/bash
su postgres -c "psql -h /var/lib/postgresql/teste-fazenda -p 5499 -d ${DB:-dreels} -qAt -v ON_ERROR_STOP=1"
