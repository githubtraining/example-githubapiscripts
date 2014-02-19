echo "Create a new Gist"
echo ...

curl -i -u githubteacher -d '{"description":"A simple Markdown example", "public":"true", "files":{"sample.md":{"content":"# Header one\nBody text"}}' https://api.github.com/gists

