ARG BUILDER_IMAGE="hexpm/elixir:1.17.3-erlang-27.0.1-debian-bookworm-20240904-slim"
ARG RUNNER_IMAGE="debian:bookworm-slim"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && \
    apt-get install -y build-essential git nodejs npm && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.deploy
RUN mix compile
COPY config/runtime.exs config/
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV MIX_ENV="prod"

WORKDIR /app

RUN chown nobody /app
RUN mkdir -p /app/uploads && chown nobody /app/uploads

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/antisocial ./

USER nobody

EXPOSE 4481

CMD ["/app/bin/antisocial", "start"]
