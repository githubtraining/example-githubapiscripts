echo "Delete githubstudent from a team."
echo ...

curl -v -H "Content-Length: 0" -n -X PUT https://api.github.com/teams/326777/members/githubstudent
