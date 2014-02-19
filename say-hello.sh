echo "Have the Octocat say hello."
echo ...

curl https://api.github.com/octocat  -G --data-urlencode "s=Hello, API student"
