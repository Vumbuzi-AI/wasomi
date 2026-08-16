# Cap concurrency. ExUnit defaults to schedulers*2 (64 on this 32-thread
# i9). test_helper cannot cap BEAM schedulers — that has to be +S at VM
# boot (see scripts/check_linters.sh).
:erlang.system_flag(:fullsweep_after, 10)

if :erlang.system_info(:schedulers_online) > 8 do
  :erlang.system_flag(:schedulers_online, 4)
end

ExUnit.start(max_cases: 2)

# Sandbox only rolls back rows created inside a test. Committed seed data
# (from MIX_ENV=test mix ecto.reset) stays visible to every test — that is
# what made admin LiveViews render the full catalogue and kill this machine.
truncate_sql = """
SELECT format('TRUNCATE TABLE %s RESTART IDENTITY CASCADE',
  string_agg(format('%I', tablename), ', '))
FROM pg_tables
WHERE schemaname = 'public' AND tablename <> 'schema_migrations'
"""

case Wasomi.Repo.query!(truncate_sql).rows do
  [[sql]] when is_binary(sql) -> Wasomi.Repo.query!(sql)
  _ -> :ok
end

Ecto.Adapters.SQL.Sandbox.mode(Wasomi.Repo, :manual)
