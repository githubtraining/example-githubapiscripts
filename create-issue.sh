echo "Create a new Issue in the example-basic repo"
echo ...

curl -i -u githubteacher -d '{"title": "A sample new issue", "body": "The user interface is upside down", "labels": ["bug"] }' https://api.github.com/repos/githubteacher/example-basic/issues
