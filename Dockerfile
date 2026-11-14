# syntax=docker/dockerfile:1

ARG RUBY_VERSION=4.0.9
FROM ruby:${RUBY_VERSION}-slim AS build

WORKDIR /app
ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    RAILS_ENV=production

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY app app
COPY bin/rails bin/rails
COPY config config
COPY lib lib
COPY public public
COPY VERSION Rakefile config.ru LICENSE.txt ./
RUN mkdir -p log tmp/pids
RUN SECRET_KEY_BASE_DUMMY=1 \
    MONGODB_URI=mongodb://127.0.0.1:27017/posebook_build \
    bundle exec rails assets:precompile

FROM ruby:${RUBY_VERSION}-slim

WORKDIR /app
ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    RAILS_ENV=production \
    PORT=3000

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

RUN groupadd --system --gid 1000 rails && \
    useradd --uid 1000 --gid 1000 --create-home rails && \
    chown -R rails:rails log tmp

USER rails
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
