# データベース係：psql / pg_dump と、2_データベース の SQL 一式
FROM public.ecr.aws/docker/library/postgres:17-alpine
WORKDIR /work
COPY 2_データベース/ /work/sql/
COPY aws/migrator/bootstrap.sql aws/migrator/post.sql aws/migrator/migrate.sh /work/
ENTRYPOINT ["/work/migrate.sh"]
