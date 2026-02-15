all:
	docker run -it --entrypoint bash -v .:/site bretfisher/jekyll -c 'bundle install && bundle exec jekyll build'

serve:
	docker compose up
