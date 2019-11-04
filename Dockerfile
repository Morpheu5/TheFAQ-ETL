FROM ruby:2.6.4

RUN mkdir -p /app
ADD . /app
WORKDIR /app
RUN gem install bundler:2.0.2
RUN bundle install
