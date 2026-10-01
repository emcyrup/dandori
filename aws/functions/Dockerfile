# 3_サーバー の Edge Functions を、Supabase と同じ実行環境（edge-runtime）でそのまま動かす
ARG EDGE_RUNTIME_TAG=v1.76.2
FROM public.ecr.aws/supabase/edge-runtime:${EDGE_RUNTIME_TAG}
COPY 3_サーバー/ /home/deno/functions/
COPY aws/functions/main/ /home/deno/functions/main/
EXPOSE 9000
CMD ["start", "--main-service", "/home/deno/functions/main", "--port", "9000", "--user-worker-request-idle-timeout", "150000"]
