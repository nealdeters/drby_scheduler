FROM ruby:3.3.10-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile* ./
RUN bundle install

COPY . .

CMD ["ruby", "/app/scripts/run.rb"]
