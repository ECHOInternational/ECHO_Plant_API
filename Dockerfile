ARG RUBY_VERSION=2.7.8
FROM ruby:${RUBY_VERSION}-slim-bullseye AS base

# --------------------------------------------------------------------------- #
# build stage: compile gems + precompile bootsnap cache                        #
# --------------------------------------------------------------------------- #
FROM base AS build

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      git \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Layer-cache the gem install — only reinstalls when Gemfile(s) change
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' \
 && bundle config set --local deployment true \
 && bundle config set --local jobs 4 \
 && bundle install

# Copy the rest of the application
COPY . .

# Warm the bootsnap cache so production boots faster
# (bootsnap >= 1.10 ships the precompile CLI)
RUN bundle exec bootsnap precompile --gemfile app/ lib/

# --------------------------------------------------------------------------- #
# production stage: lean runtime image                                         #
# --------------------------------------------------------------------------- #
FROM base AS production

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      libpq5 \
      libjemalloc2 \
 && rm -rf /var/lib/apt/lists/*

# Arch-safe jemalloc preload: create a stable symlink at a fixed path
# so LD_PRELOAD works on both x86_64 and arm64.
RUN ln -s "/usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2" /usr/local/lib/libjemalloc.so.2

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    BUNDLE_WITHOUT="development:test"

# Create the app user/group BEFORE copying files so COPY --chown works
# without a separate chown layer (avoids duplicating content across layers).
RUN groupadd --gid 1000 app \
 && useradd --uid 1000 --gid app --shell /bin/bash --create-home app

WORKDIR /app

# Copy installed gems and app from build stage, already owned by app:app
COPY --chown=app:app --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=app:app --from=build /app /app

USER app

# Ensure the pids directory exists and is writable by the app user
RUN mkdir -p tmp/pids

EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

# --------------------------------------------------------------------------- #
# development stage: full dev environment matching current docker-compose      #
# --------------------------------------------------------------------------- #
FROM base AS development

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      git \
      postgresql-client \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /myapp

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

# PID cleanup entrypoint (dev only)
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
