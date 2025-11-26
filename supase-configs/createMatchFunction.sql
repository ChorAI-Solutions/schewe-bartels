drop function if exists public.match_documents(vector(1536), integer);

create or replace function public.match_documents(
  query_embedding vector(1536),
  match_count int default 5,
  filter jsonb default '{}'::jsonb
) returns table(
  id bigint,
  content text,
  metadata jsonb,
  similarity double precision
) language plpgsql stable as $$
declare
  filter_payload jsonb := coalesce(filter, '{}'::jsonb);
begin
  return query
  select
    d.id,
    d.content,
    d.metadata,
    1 - (d.embedding <=> query_embedding) as similarity
  from documents_pg d
  where filter_payload = '{}'::jsonb
        or d.metadata @> filter_payload
  order by d.embedding <=> query_embedding
  limit match_count;
end;
$$;