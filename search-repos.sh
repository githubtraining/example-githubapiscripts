echo "Search for repositories with the word asteroids, written in Java, sorted by stars."
echo ...

curl https://api.github.com/search/repositories\?q\=asteroids+language:java\&sort\=stars\&order\=desc
