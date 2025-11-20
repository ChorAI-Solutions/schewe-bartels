create or replace function match_function(
  query_embedding vector(1536),
  match_count int default 5,
  min_similarity float default 0.7
) returns table(
  id int,
  content text,
  metadata jsonb,
  similarity float
) language sql stable as $$
  select
    t.id,
    t.content,
    t.metadata,
    1 - (t.embedding <=> query_embedding) as similarity
  from everlast_rag t
  where 1 - (t.embedding <=> query_embedding) >= min_similarity
  order by t.embedding <=> query_embedding
  limit match_count;
$$;