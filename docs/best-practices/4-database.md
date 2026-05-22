# Database Best Practices

> **STATUS: TEMPLATE SEED**
>
> This file ships with the framework template and contains general database best practices
> that apply regardless of which database engine or ORM your project uses.
>
> After running the project setup agent (`docs/workflow/setup/protocol.md`), add your
> project-specific conventions in [`stack/`](stack/) files and link them from
> [`STACK-SPECIFIC.md`](STACK-SPECIFIC.md).

---

## Migrations

- Keep migrations small and reversible whenever possible.
- Never edit a migration file that has already been applied in any environment; create a
  new one instead.
- Test every migration against a production-representative dataset before applying to
  staging or production.
- Run `EXPLAIN ANALYZE` on queries that touch columns affected by a new index or schema
  change before shipping.

---

## Row-Level Security (RLS)

### Enabling RLS on a new table

When creating a new table, enable RLS immediately after the `CREATE TABLE` statement and
define all policies in the same migration:

```sql
CREATE TABLE public.my_table ( ... );

ALTER TABLE public.my_table ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users can read their own rows"
  ON public.my_table FOR SELECT
  USING (auth.uid() = user_id);
```

### Enabling RLS on an existing table — safety checklist

When retrofitting RLS onto a table that already exists in production, follow these steps
in order. Skipping Step 1 is a common security mistake: legacy `GRANT` statements survive
the `ALTER TABLE` and can expose more rows than intended if policies are incomplete or
overly permissive during rollout.

1. **Revoke broad grants before enabling RLS.**
   Pre-existing grants (e.g. `GRANT SELECT ON public.my_table TO public`) increase the
   blast radius: if any RLS policy is incomplete or missing during rollout, more rows
   than intended are exposed. Both table privileges and RLS policies are required to
   restrict access — neither control bypasses the other. Revoke broad grants first to
   limit that blast radius:

   ```sql
   -- Revoke from every role that should no longer have unrestricted access.
   -- Adjust the role list to match your auth setup (e.g. anon, authenticated, service_role).
   REVOKE ALL ON public.my_table FROM public, anon, authenticated;
   ```

2. **Enable RLS.**

   ```sql
   ALTER TABLE public.my_table ENABLE ROW LEVEL SECURITY;
   ```

3. **Define your policies.**

   ```sql
   CREATE POLICY "users can read their own rows"
     ON public.my_table FOR SELECT
     USING (auth.uid() = user_id);
   ```

4. **Re-grant only what each role needs** (if anything).
   If a role requires read access but must still go through policies, grant `SELECT` back
   after policies are in place:

   ```sql
   -- Only if the role needs access that a policy will filter:
   GRANT SELECT ON public.my_table TO authenticated;
   ```

5. **Verify with a smoke test** against a staging environment: confirm that a row owned
   by user A is not visible to user B, and that service-role access still works if
   required.

> **Why this order matters**: PostgreSQL access control combines table privileges (GRANT)
> and RLS policies as layered, complementary controls — both must permit access for a
> user to see rows. A `GRANT SELECT TO public` grants table-level access, but RLS
> policies further restrict which rows are visible. The risk is not that grants override
> policies; it is that a broad grant **expands the blast radius** if any policy is
> incomplete or missing during a migration. The safe order is REVOKE → ENABLE → CREATE
> POLICY → re-GRANT, so the blast radius is minimised throughout the transition.
> See the [PostgreSQL Row Security Policies documentation](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
> for the authoritative reference.

---

## General Access Control

- Apply the principle of least privilege: grant only the permissions a role or user
  actually needs.
- Prefer explicit, narrow grants over broad ones (e.g. `SELECT` on specific tables rather
  than `ALL PRIVILEGES ON SCHEMA public`).
- Audit existing grants whenever a security-sensitive migration is applied.
