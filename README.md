# Supabase Docker

This is a minimal Docker Compose setup for self-hosting Supabase. Follow the steps [here](https://supabase.com/docs/guides/hosting/docker) to get started.

# Backups

1. Run `./backup.sh [DATABASE_URL]` to generate dumps.  
   Example: `./backup.sh postgresql://postgres:PASSWORD@HOST:5432/postgres`
2. The script writes three timestamped files under `dump/`: roles, schema and data.
3. Alternatively, run `docker compose run --rm backup` to execute the same script inside the `supabase-backup` service. The generated files are still written to the `dump/` directory on the host.

# Restore

1. Copy each dump into the `supabase-db` container:
   - `sudo docker cp path/to/schema.sql supabase-db:/schema.sql`
   - `sudo docker cp path/to/roles.sql supabase-db:/roles.sql`
   - `sudo docker cp path/to/data.sql supabase-db:/data.sql`
2. Execute the SQL files (schema → roles → data):
   - `sudo docker exec -it supabase-db psql -U postgres -W postgres -f /schema.sql`
   - `sudo docker exec -it supabase-db psql -U postgres -W postgres -f /roles.sql`
   - `sudo docker exec -it supabase-db psql -U postgres -W postgres -f /data.sql`
