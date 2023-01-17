.PHONY: start
start:
	docker build -t monzo-task .; docker run -p 8080:8080 monzo-task --rm