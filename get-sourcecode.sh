echo "Retrieving the source code for the Ruby .gitignore template."
echo ...

curl https://api.github.com/gitignore/templates/Ruby

echo ...
echo "Look for the html_url field in the output."
