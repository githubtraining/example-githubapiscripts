echo "Retrieving information about the githubtraining user's authorized applications"
echo ...

curl -u githubteacher -d '{"scopes":["public_repo"]}' -X GET https://api.github.com/authorizations
